defmodule GorgonSurvey.SurveyDetector do
  @moduledoc "Detects red circle survey markers and player triangle in game screenshots."

  use Image.Math

  # Red circle detection
  @red_min 150
  @green_max 80
  @blue_max 80
  @cluster_distance 30
  @min_cluster_pixels 10
  @max_cluster_pixels 500
  @max_aspect_ratio 3.0

  # Player triangle detection — bright near-white pixels (all channels high and close)
  @player_brightness_min 200
  @player_channel_spread 40
  @player_min_pixels 5
  @player_max_pixels 200
  @player_cluster_distance 15
  @doc """
  Detects red circles in an image binary.
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
      raw_clusters = cluster_raw(coords)

      require Logger
      Logger.info("[detect] #{length(coords)} red pixels, #{length(raw_clusters)} raw clusters")

      for c <- raw_clusters do
        n = length(c)
        {cx, cy} = centroid(c)
        {xs, ys} = Enum.unzip(c)
        bw = Enum.max(xs) - Enum.min(xs) + 1
        bh = Enum.max(ys) - Enum.min(ys) + 1
        Logger.info("[detect] cluster: #{n}px, bbox=#{bw}x#{bh}, center=(#{round(cx)},#{round(cy)})")
      end

      clusters = raw_clusters
        |> Enum.filter(fn cluster ->
          n = length(cluster)
          n >= @min_cluster_pixels and n <= @max_cluster_pixels and circular?(cluster)
        end)

      Logger.info("[detect] #{length(clusters)} clusters after filtering")

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

  @doc """
  Detects the player triangle (bright near-white) in an image binary.
  Returns {:ok, {x_pct, y_pct}} or {:ok, nil} if not found.
  """
  def detect_player(png_binary) do
    with {:ok, img} <- Image.from_binary(png_binary) do
      width = Image.width(img)
      height = Image.height(img)

      [r, g, b | _] = Image.split_bands(img)

      # All channels must be bright and close together (near-white, low saturation)
      bright = (r > @player_brightness_min) &&& (g > @player_brightness_min) &&& (b > @player_brightness_min)
      # Check pairwise channel differences are small
      rg_close = Vix.Vips.Operation.abs!(r - g) < @player_channel_spread
      rb_close = Vix.Vips.Operation.abs!(r - b) < @player_channel_spread
      gb_close = Vix.Vips.Operation.abs!(g - b) < @player_channel_spread
      mask = bright &&& rg_close &&& rb_close &&& gb_close

      {:ok, tensor} = Vix.Vips.Image.write_to_tensor(mask)
      {_h, w, _bands} = tensor.shape

      coords = mask_pixel_coords(tensor.data, w)
      clusters = cluster_with_distance(coords, @player_cluster_distance)
        |> Enum.filter(fn cluster ->
          n = length(cluster)
          n >= @player_min_pixels and n <= @player_max_pixels and circular?(cluster)
        end)

      require Logger
      Logger.info("[detect_player] #{length(coords)} bright pixels, #{length(clusters)} clusters")

      for c <- clusters do
        n = length(c)
        {cx, cy} = bbox_center(c)
        Logger.info("[detect_player] cluster: #{n}px, center=(#{round(cx)},#{round(cy)})")
      end

      # Pick the smallest matching cluster (player triangle is small and isolated)
      case Enum.sort_by(clusters, &length/1) do
        [best | _] ->
          {cx, cy} = bbox_center(best)
          {:ok, {cx / width * 100, cy / height * 100}}
        [] ->
          {:ok, nil}
      end
    end
  end

  defp mask_pixel_coords(data, width) do
    for <<byte <- data>>, reduce: {[], 0} do
      {acc, idx} ->
        if byte > 0 do
          {[{rem(idx, width), div(idx, width)} | acc], idx + 1}
        else
          {acc, idx + 1}
        end
    end
    |> elem(0)
    |> Enum.reverse()
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

  defp cluster_with_distance([], _dist), do: []

  defp cluster_with_distance(coords, dist) do
    Enum.reduce(coords, [], fn {x, y}, clusters ->
      case Enum.find_index(clusters, fn cluster ->
             {cx, cy} = centroid(cluster)
             Kernel.abs(cx - x) < dist and Kernel.abs(cy - y) < dist
           end) do
        nil -> clusters ++ [[{x, y}]]
        idx -> List.update_at(clusters, idx, &[{x, y} | &1])
      end
    end)
    |> Enum.filter(fn cluster -> length(cluster) > 3 end)
  end

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

  defp circular?(cluster) do
    {xs, ys} = Enum.unzip(cluster)
    w = Enum.max(xs) - Enum.min(xs) + 1
    h = Enum.max(ys) - Enum.min(ys) + 1
    ratio = if h > 0 and w > 0, do: max(w / h, h / w), else: 999.0
    ratio <= @max_aspect_ratio
  end

  # Bounding box center — true geometric center for circle outlines
  defp bbox_center(points) do
    {xs, ys} = Enum.unzip(points)
    {(Enum.min(xs) + Enum.max(xs)) / 2, (Enum.min(ys) + Enum.max(ys)) / 2}
  end

  # Pixel average centroid — used for clustering proximity
  defp centroid(points) do
    n = length(points)
    {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
    {sum_x / n, sum_y / n}
  end
end
