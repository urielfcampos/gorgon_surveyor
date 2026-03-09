defmodule GorgonSurvey.SurveyDetector do
  @moduledoc "Detects red circle survey markers in game screenshots."

  use Image.Math

  @red_min 150
  @green_max 80
  @blue_max 80
  @cluster_distance 30

  @doc """
  Detects red circles in a PNG binary image.
  Returns {:ok, [{x_pct, y_pct}, ...]} sorted left-to-right, top-to-bottom.
  Percentages are relative to image dimensions.
  """
  def detect(png_binary) do
    with {:ok, img} <- Image.from_binary(png_binary) do
      width = Image.width(img)
      height = Image.height(img)

      [r, g, b | _] = Image.split_bands(img)
      mask = (r > @red_min) &&& (g < @green_max) &&& (b < @blue_max)

      {:ok, tensor} = Vix.Vips.Image.write_to_tensor(mask)
      {h, w, _bands} = tensor.shape

      coords = red_pixel_coords(tensor.data, w, h)
      clusters = cluster_coords(coords)

      centroids =
        clusters
        |> Enum.map(fn cluster ->
          {cx, cy} = centroid(cluster)
          {cx / width * 100, cy / height * 100}
        end)
        |> Enum.sort_by(fn {x, y} -> {round(y / 10), x} end)

      {:ok, centroids}
    end
  end

  defp red_pixel_coords(data, width, _height) do
    pixels = for <<byte <- data>>, do: byte

    pixels
    |> Enum.with_index()
    |> Enum.filter(fn {val, _idx} -> val > 0 end)
    |> Enum.map(fn {_val, idx} ->
      x = rem(idx, width)
      y = div(idx, width)
      {x, y}
    end)
  end

  defp cluster_coords([]), do: []

  defp cluster_coords(coords) do
    Enum.reduce(coords, [], fn {x, y}, clusters ->
      case Enum.find_index(clusters, fn cluster ->
             {cx, cy} = centroid(cluster)
             Kernel.abs(cx - x) < @cluster_distance and Kernel.abs(cy - y) < @cluster_distance
           end) do
        nil -> clusters ++ [[{x, y}]]
        idx -> List.update_at(clusters, idx, &[{x, y} | &1])
      end
    end)
    |> Enum.filter(fn cluster -> length(cluster) > 5 end)
  end

  defp centroid(points) do
    n = length(points)
    {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
    {sum_x / n, sum_y / n}
  end
end
