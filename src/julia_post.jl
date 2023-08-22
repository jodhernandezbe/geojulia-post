# Install packages
import GeoDataFrames as GDF
using GeometryBasics
using ColorTypes
using ArchGDAL
using DataFrames
using CSV
using Plots

function plot_earthquakes_scatter(earthquakes, usa_gdf, parent_folder)
      """
      Plot earthquakes on the USA map
      
      Parameters:
      - earthquakes (DataFrame): DataFrame containing earthquake data
      - usa_gdf (GeoDataFrame): GeoDataFrame containing USA map data
      - parent_folder (String): Parent folder containing the project

      Returns:
        Nothing. The figure is saved as 'earthquakes_scatter.png'
      """

      # Filter rows based on magnitude ranges
      low_mag_df = earthquakes[earthquakes.mag .<= 2.5, [:mag, :latitude, :longitude]]
      medium_mag_df = earthquakes[(2.5 .< earthquakes.mag .<= 4.5), [:mag, :latitude, :longitude]]
      high_mag_df = earthquakes[earthquakes.mag .> 4.5, [:mag, :latitude, :longitude]]

      # Plot continental USA map
      plot(usa_gdf.geometry,
            seriestype=:path,
            linecolor=:gray,
            fillalpha=0,
            legend=false,
            xlims=(-130, -65),
            ylims=(20, 50),
            showaxis=false,
            grid=false)

      # Plot earthquake points
      scatter!(low_mag_df.longitude, low_mag_df.latitude,
            color=:blue, label="Mag <= 2.5", alpha=0.5)
      scatter!(medium_mag_df.longitude, medium_mag_df.latitude,
            color=:green, label="2.5 < Mag <= 4.5", alpha=0.5)
      scatter!(high_mag_df.longitude, high_mag_df.latitude,
            color=:red, label="Mag > 4.5", alpha=0.5)

      # Customize the plot
      plot!(legend=:outertop, legendcolumns=3)

      # Save the plot
      savefig(joinpath(parent_folder, "plots", "earthquakes_scatter.png"))
end

function plot_earthquakes_tri(earthquakes, usa_gdf, tri, parent_folder)
      """
      Plots earthquake data on a map of the USA, overlaying triangular regions and facilities.

      Parameters:
      - earthquakes (DataFrame): Earthquake data including depth, latitude, and longitude.
      - usa_gdf (GeoDataFrame): GeoDataFrame representing the map of the USA.
      - tri (DataFrame): DataFrame containing triangular regions.
      - parent_folder (String): Path to the parent folder where the plot will be saved.

      Returns:
      - Nothing. The figure is saved as 'earthquakes_tri.png'
      """

      joined_df = DataFrame(amount = Float64[], latitude = Float64[], longitude = Float64[], geometry = Any[])
        
      # Iterate through each row in the "tri" DataFrame
      for row in eachrow(tri)
            point = [row.longitude, row.latitude]
            # Iterate through each row in the "usa_gdf" GeoDataFrame
            for geo_row in eachrow(usa_gdf)
                  if point_inside_polygon(point, geo_row.geometry)
                        push!(joined_df, (amount = row.amount, latitude = row.latitude, longitude = row.longitude, geometry = geo_row.geometry))
                        break
                  end
            end
      end
      grouped_df = combine(groupby(joined_df, :geometry), :amount => sum)
      min_amount_sum = minimum(grouped_df.amount_sum)
      max_amount_sum = maximum(grouped_df.amount_sum)
      grouped_df.normalized_amount_sum = (grouped_df.amount_sum .- min_amount_sum) / (max_amount_sum - min_amount_sum)

      # Plot continental USA map
      p = plot(usa_gdf.geometry,
            seriestype=:path,
            linecolor=:gray,
            fillalpha=0.7,
            legend=false,
            xlims=(-130, -65),
            ylims=(20, 50),
            showaxis=false,
            grid=false)

      color_palette = [] 
      amounts = []
      for geo_row in eachrow(grouped_df)
            rgb_value = round(- 250.0 * geo_row.normalized_amount_sum + 250.0)
            amount_color = RGB(rgb_value/255, rgb_value/255, 1.0)
            push!(color_palette, amount_color)
            push!(amounts, geo_row.amount_sum)
            plot!(geo_row.geometry,
                  seriestype=:shape,
                  color=amount_color,
                  alpha=0.2)
      end

      # Plot earthquake points
      earthquakes = earthquakes[earthquakes.mag .>= 4, [:depth, :latitude, :longitude]]
      scatter!(earthquakes.longitude, earthquakes.latitude,
            color=:red, alpha=0.5, markersize=earthquakes.depth)
      scatter!(earthquakes.longitude,
            earthquakes.latitude,
            markersize = 1,
            markercolor = :black,
            legend = false)

      # Plot facilities
      scatter!(tri.longitude,
            tri.latitude,
            markersize = 3,
            markercolor = :purple,
            legend = false)

      # Save the plot
      savefig(joinpath(parent_folder, "plots", "earthquakes_tri.png"))

end

function point_inside_polygon(point, shape)
      """
      Check if a given point is inside a polygon shape.

      Args:
      - point (Tuple): Coordinates (longitude, latitude) of the point.
      - shape (Geometry): Polygon shape to check against.

      Returns:
      - Bool: True if the point is inside the polygon, False otherwise.
"""
      return ArchGDAL.within(ArchGDAL.createpoint(point[1], point[2]), shape)
end

# Get the current file path
current_file = @__FILE__

# Get the parent folder path
parent_folder = dirname(dirname(current_file))

# Read shapes for the USA map
usa_gdf = GDF.read(
              joinpath(parent_folder, "data", "cb_2018_us_state_500k.shp")
              )

# Read earthquakes
earthquakes = DataFrame(CSV.File(joinpath(parent_folder, "data", "earthquakes.csv")))
earthquakes = earthquakes[earthquakes.status .== "reviewed", [:mag, :latitude, :longitude, :depth]]


# Read the U.S. Toxics Release Iventory data
tri = DataFrame(CSV.File(joinpath(parent_folder, "data", "tri.csv")))
tri = tri[(tri.CAS_CHEM_NAME .== "n-Hexane") .& (tri.TOTAL_ON_OFF_SITE_RELEASE .!= 0),
          [:TOTAL_ON_OFF_SITE_RELEASE, :LATITUDE, :LONGITUDE]]
rename!(tri, :TOTAL_ON_OFF_SITE_RELEASE => :amount,
      :LATITUDE => :latitude,
      :LONGITUDE => :longitude)
dropmissing!(tri, disallowmissing=true)
tri.amount = tri.amount .* 0.453592 # Convert the column from pounds to kilograms

# Plot earthquakes
plot_earthquakes_scatter(earthquakes, usa_gdf, parent_folder)
plot_earthquakes_tri(earthquakes, usa_gdf, tri, parent_folder)