defmodule GorgonSurvey.SurveyDetector do
  @moduledoc """
  Detects red circle survey markers in game screenshots.

  ## How it works

  Survey markers in Project Gorgon appear as small red circles on the minimap.
  Detection is a three-stage pipeline:

  1. **Color thresholding** — Split the image into RGB bands and build a binary
     mask of pixels that are "red enough" (R > 150, G < 80, B < 80). This
     isolates survey markers from the rest of the minimap.

  2. **Clustering** — Group nearby red pixels into clusters using a simple
     proximity-based algorithm: each pixel is added to the nearest existing
     cluster (within @cluster_distance px of its centroid), or starts a new
     cluster. Tiny noise clusters (< 4 px) are discarded.

  3. **Filtering & output** — Keep only clusters that look like circles:
     between @min_cluster_pixels and @max_cluster_pixels, with a bounding-box
     aspect ratio under @max_aspect_ratio. Return the bounding-box center of
     each surviving cluster as percentage coordinates, sorted roughly
     left-to-right, top-to-bottom.
  """

  use Image.Math

  require Logger

  # Color thresholds for the red channel mask.
  # Pixels must have R above min AND G/B below max to qualify.
  @red_min 150
  @green_max 80
  @blue_max 80

  # Max distance (px) from a cluster's centroid for a pixel to join it.
  @cluster_distance 30

  # Cluster size bounds — filters out noise (too small) and large red UI
  # elements (too big) that aren't survey markers.
  @min_cluster_pixels 10
  @max_cluster_pixels 500

  # Bounding-box aspect ratio limit — rejects elongated shapes (lines, bars)
  # that pass the size filter but aren't circular markers.
  @max_aspect_ratio 3.0

  @doc """
  Detects red circles in an image binary.
  Returns {:ok, [{x_pct, y_pct}, ...]} sorted left-to-right, top-to-bottom.
  Percentages are relative to image dimensions.
  """
  def detect(png_binary) do
    with {:ok, img} <- Image.from_binary(png_binary) do
      width = Image.width(img)
      height = Image.height(img)

      # Stage 1: Build a binary mask of red pixels by thresholding each channel.
      # The &&& operator is a band-wise AND from Image.Math (not Bitwise).
      [r, g, b | _] = Image.split_bands(img)
      mask = r > @red_min &&& g < @green_max &&& b < @blue_max

      # Convert the mask image to a raw tensor so we can iterate over pixels.
      {:ok, tensor} = Vix.Vips.Image.write_to_tensor(mask)
      {h, w, _bands} = tensor.shape

      # Extract {x, y} coordinates of all non-zero (red) pixels.
      coords = red_pixel_coords(tensor.data, w, h)

      # Stage 2: Group red pixels into clusters by proximity.
      raw_clusters = cluster_raw(coords)

      Logger.info("[detect] #{length(coords)} red pixels, #{length(raw_clusters)} raw clusters")

      for c <- raw_clusters do
        n = length(c)
        {cx, cy} = centroid(c)
        {xs, ys} = Enum.unzip(c)
        bw = Enum.max(xs) - Enum.min(xs) + 1
        bh = Enum.max(ys) - Enum.min(ys) + 1

        Logger.info(
          "[detect] cluster: #{n}px, bbox=#{bw}x#{bh}, center=(#{round(cx)},#{round(cy)})"
        )
      end

      # Stage 3: Filter clusters by size and shape (must be roughly circular).
      clusters =
        raw_clusters
        |> Enum.filter(fn cluster ->
          n = length(cluster)
          n >= @min_cluster_pixels and n <= @max_cluster_pixels and circular?(cluster)
        end)

      Logger.info("[detect] #{length(clusters)} clusters after filtering")

      # Convert cluster centers to percentage coordinates and sort by row then column.
      # Rows are bucketed into bands of 10% height to get a stable left-to-right order.
      centroids =
        clusters
        |> Enum.map(fn cluster ->
          {cx, cy} = bbox_center(cluster)
          {cx / width * 100, cy / height * 100}
        end)
        |> Enum.sort_by(fn {x, y} -> {round(y / 10), x} end)

      {:ok, centroids}
    end
  end

  # Walks the raw mask tensor bytes and returns {x, y} for every non-zero pixel.
  # The tensor is a flat 1D binary where each byte is one pixel (0 or 255).
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

  # Groups pixel coordinates into clusters using nearest-centroid assignment.
  # For each pixel, find the cluster whose centroid is within @cluster_distance;
  # if none exists, start a new cluster. Clusters with <= 3 pixels are noise.
  defp cluster_raw([]), do: []

  defp cluster_raw(coords) do
    Enum.reduce(coords, [], fn {x, y}, clusters ->
      case Enum.find_index(clusters, fn cluster ->
             {cx, cy} = centroid(cluster)
             Kernel.abs(cx - x) < @cluster_distance and Kernel.abs(cy - y) < @cluster_distance
           end) do
        nil -> clusters ++ [[{x, y}]]
        idx -> List.update_at(clusters, idx, &[{x, y} | &1])
      end
    end)
    |> Enum.filter(fn cluster -> length(cluster) > 3 end)
  end

  # Checks if a cluster's bounding box is roughly square (aspect ratio within limit).
  # Survey markers are circles, so their bounding box should be close to 1:1.
  defp circular?(cluster) do
    {xs, ys} = Enum.unzip(cluster)
    w = Enum.max(xs) - Enum.min(xs) + 1
    h = Enum.max(ys) - Enum.min(ys) + 1
    ratio = if h > 0 and w > 0, do: max(w / h, h / w), else: 999.0
    ratio <= @max_aspect_ratio
  end

  # Bounding box center — midpoint of min/max coordinates.
  # More stable than pixel-average centroid for hollow circle outlines where
  # pixels concentrate on the perimeter.
  defp bbox_center(points) do
    {xs, ys} = Enum.unzip(points)
    {(Enum.min(xs) + Enum.max(xs)) / 2, (Enum.min(ys) + Enum.max(ys)) / 2}
  end

  # Pixel-average centroid — mean of all pixel positions in a cluster.
  # Used during clustering to decide which cluster a new pixel belongs to.
  defp centroid(points) do
    n = length(points)
    {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
    {sum_x / n, sum_y / n}
  end
end
