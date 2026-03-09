# Auto-Detect Survey Markers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically detect red circle survey markers in screen capture frames and place them on the overlay.

**Architecture:** JS hook periodically captures video frames as PNG, sends to server. Server uses `image` (libvips) to color-filter for red pixels, clusters them spatially, finds centroids, and matches to unplaced surveys in order. Toggle in sidebar controls the scan loop.

**Tech Stack:** `image` hex package (libvips), `Nx` for tensor clustering, Phoenix LiveView push events.

---

### Task 1: Add `image` dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Add dep**

Add to the deps list in `mix.exs`:

```elixir
{:image, "~> 0.54"},
```

**Step 2: Install**

Run: `mise exec -- mix deps.get`
Expected: deps fetched successfully

**Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add image package for survey detection"
```

---

### Task 2: Create SurveyDetector module with red pixel detection

**Files:**
- Create: `lib/gorgon_survey/survey_detector.ex`
- Create: `test/gorgon_survey/survey_detector_test.exs`

**Step 1: Write the test**

```elixir
defmodule GorgonSurvey.SurveyDetectorTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.SurveyDetector

  describe "detect/1" do
    test "returns empty list for image with no red circles" do
      # Create a 100x100 blue image
      {:ok, img} = Image.new(100, 100, color: [0, 0, 255])
      {:ok, png} = Image.write(img, :memory, suffix: ".png")
      assert {:ok, []} = SurveyDetector.detect(png)
    end

    test "detects a single red circle" do
      # Create a 200x200 black image with a red circle in the center
      {:ok, bg} = Image.new(200, 200, color: [0, 0, 0])
      {:ok, circle} = Image.Shape.circle(15, fill_color: [255, 0, 0])
      {:ok, img} = Image.compose(bg, circle, x: 85, y: 85)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      assert {:ok, [{x_pct, y_pct}]} = SurveyDetector.detect(png)
      # Center should be roughly at 50%, 50% (within tolerance)
      assert_in_delta x_pct, 50.0, 5.0
      assert_in_delta y_pct, 50.0, 5.0
    end

    test "detects multiple red circles" do
      {:ok, bg} = Image.new(300, 300, color: [0, 0, 0])
      {:ok, circle} = Image.Shape.circle(10, fill_color: [255, 0, 0])
      {:ok, img} = Image.compose(bg, circle, x: 40, y: 40)
      {:ok, img} = Image.compose(img, circle, x: 240, y: 240)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      assert {:ok, circles} = SurveyDetector.detect(png)
      assert length(circles) == 2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mise exec -- mix test test/gorgon_survey/survey_detector_test.exs`
Expected: FAIL — module not found

**Step 3: Write the SurveyDetector module**

```elixir
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

      {:ok, [r, g, b | _]} = Image.split_bands(img)
      mask = (r > @red_min) &&& (g < @green_max) &&& (b < @blue_max)

      # Convert mask to Nx tensor to find red pixel coordinates
      {:ok, tensor} = Vix.Vips.Image.write_to_tensor(mask)
      flat = Nx.from_binary(tensor.data, :u8)
        |> Nx.reshape({height, width})

      coords = red_pixel_coords(flat)
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

  defp red_pixel_coords(tensor) do
    # Find all coordinates where mask is 255 (true)
    {h, w} = Nx.shape(tensor)
    for y <- 0..(h - 1),
        x <- 0..(w - 1),
        Nx.to_number(tensor[y][x]) > 0,
        do: {x, y}
  end

  defp cluster_coords([]), do: []
  defp cluster_coords(coords) do
    # Simple greedy clustering: assign each point to nearest cluster or create new one
    Enum.reduce(coords, [], fn {x, y}, clusters ->
      case Enum.find_index(clusters, fn cluster ->
        {cx, cy} = centroid(cluster)
        abs(cx - x) < @cluster_distance and abs(cy - y) < @cluster_distance
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
```

**Step 4: Run tests**

Run: `mise exec -- mix test test/gorgon_survey/survey_detector_test.exs`
Expected: PASS (adjust test tolerances or Image.Shape API if needed)

**Step 5: Commit**

```bash
git add lib/gorgon_survey/survey_detector.ex test/gorgon_survey/survey_detector_test.exs
git commit -m "feat: add SurveyDetector module for red circle detection"
```

---

### Task 3: Add LiveView auto-detect events and assigns

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.ex`

**Step 1: Add `auto_detect` assign in mount**

In `mount/3`, add `auto_detect: false` to the assign list:

```elixir
{:ok, assign(socket,
  app_state: state,
  sharing: false,
  placing_survey: nil,
  log_folder: log_folder,
  auto_detect: false
)}
```

**Step 2: Add toggle event handler**

```elixir
@impl true
def handle_event("toggle_auto_detect", _params, socket) do
  auto_detect = !socket.assigns.auto_detect
  socket = assign(socket, auto_detect: auto_detect)

  socket = if auto_detect do
    push_event(socket, "start_auto_detect", %{})
  else
    push_event(socket, "stop_auto_detect", %{})
  end

  {:noreply, socket}
end
```

**Step 3: Add scan_frame event handler**

```elixir
@impl true
def handle_event("scan_frame", %{"data" => data_url}, socket) do
  # Strip "data:image/png;base64," prefix
  png_binary = data_url
    |> String.split(",", parts: 2)
    |> List.last()
    |> Base.decode64!()

  case GorgonSurvey.SurveyDetector.detect(png_binary) do
    {:ok, circles} ->
      # Match circles to unplaced surveys in order
      unplaced = Enum.filter(socket.assigns.app_state.surveys, &is_nil(&1.x_pct))

      Enum.zip(unplaced, circles)
      |> Enum.each(fn {survey, {x_pct, y_pct}} ->
        LogWatcher.place_survey(survey.id, x_pct, y_pct)
      end)

      {:noreply, socket}

    _ ->
      {:noreply, socket}
  end
end
```

**Step 4: Verify compilation**

Run: `mise exec -- mix compile --warnings-as-errors`
Expected: compiles cleanly

**Step 5: Commit**

```bash
git add lib/gorgon_survey_web/live/survey_live.ex
git commit -m "feat: add auto-detect LiveView events and scan_frame handler"
```

---

### Task 4: Add JS hook frame capture

**Files:**
- Modify: `assets/js/hooks/screen_capture.js`

**Step 1: Add auto-detect event listeners and capture logic**

In the `mounted()` function, after the existing `handleEvent` calls, add:

```javascript
this.scanInterval = null;
this.scanCanvas = document.createElement("canvas");

this.handleEvent("start_auto_detect", () => {
  if (this.scanInterval) return;
  this.scanInterval = setInterval(() => this.captureFrame(), 3000);
});

this.handleEvent("stop_auto_detect", () => {
  if (this.scanInterval) {
    clearInterval(this.scanInterval);
    this.scanInterval = null;
  }
});
```

Add a new method `captureFrame()`:

```javascript
captureFrame() {
  if (!this.video || !this.video.videoWidth) return;
  this.scanCanvas.width = this.video.videoWidth;
  this.scanCanvas.height = this.video.videoHeight;
  const ctx = this.scanCanvas.getContext("2d");
  ctx.drawImage(this.video, 0, 0);
  const dataUrl = this.scanCanvas.toDataURL("image/png");
  this.pushEvent("scan_frame", { data: dataUrl });
},
```

In the `destroyed()` callback, add interval cleanup:

```javascript
destroyed() {
  if (this.stream) {
    this.stream.getTracks().forEach(t => t.stop());
  }
  if (this.scanInterval) {
    clearInterval(this.scanInterval);
  }
}
```

**Step 2: Verify it builds**

Run: `mise exec -- npx vite build`
Expected: builds without errors

**Step 3: Commit**

```bash
git add assets/js/hooks/screen_capture.js
git commit -m "feat: add periodic frame capture for auto-detect"
```

---

### Task 5: Add auto-detect toggle to template

**Files:**
- Modify: `lib/gorgon_survey_web/live/survey_live.html.heex`
- Modify: `assets/css/app.css`

**Step 1: Add toggle button in sidebar**

After the "Clear All" button and before the settings section, add:

```heex
<button phx-click="toggle_auto_detect" class={"detect-btn #{if @auto_detect, do: "active"}"}>
  <%= if @auto_detect, do: "Stop Auto-Detect", else: "Auto-Detect" %>
</button>
```

**Step 2: Add CSS for the button**

In `assets/css/app.css`, after the `.clear-btn` styles, add:

```css
.detect-btn {
  width: 100%;
  padding: 6px;
  background: #2a5a2a;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  margin-top: 4px;
}

.detect-btn.active {
  background: #5a2a2a;
}
```

**Step 3: Verify the app works end-to-end**

Run: `WEBKIT_DISABLE_DMABUF_RENDERER=1 mise exec -- mix phx.server`

1. Open http://localhost:4000
2. Share screen
3. Set log folder and trigger some surveys
4. Click "Auto-Detect" — should start scanning frames
5. Red circles in the video should auto-place markers

**Step 4: Commit**

```bash
git add lib/gorgon_survey_web/live/survey_live.html.heex assets/css/app.css
git commit -m "feat: add auto-detect toggle button to sidebar"
```
