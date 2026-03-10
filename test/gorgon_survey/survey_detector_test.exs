defmodule GorgonSurvey.SurveyDetectorTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.SurveyDetector

  describe "detect/1" do
    test "returns empty list for image with no red circles" do
      {:ok, img} = Image.new(100, 100, color: [0, 0, 255])
      {:ok, png} = Image.write(img, :memory, suffix: ".png")
      assert {:ok, []} = SurveyDetector.detect(png)
    end

    test "detects a single red circle" do
      {:ok, bg} = Image.new(200, 200, color: [0, 0, 0])
      {:ok, circle} = Image.Shape.circle(10, fill_color: [255, 0, 0])
      {:ok, img} = Image.compose(bg, circle, x: 90, y: 90)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      assert {:ok, [{x_pct, y_pct}]} = SurveyDetector.detect(png)
      assert_in_delta x_pct, 50.0, 5.0
      assert_in_delta y_pct, 50.0, 5.0
    end

    test "detects multiple red circles" do
      {:ok, bg} = Image.new(300, 300, color: [0, 0, 0])
      {:ok, circle} = Image.Shape.circle(8, fill_color: [255, 0, 0])
      {:ok, img} = Image.compose(bg, circle, x: 42, y: 42)
      {:ok, img} = Image.compose(img, circle, x: 242, y: 242)
      {:ok, png} = Image.write(img, :memory, suffix: ".png")

      assert {:ok, circles} = SurveyDetector.detect(png)
      assert length(circles) == 2
    end
  end
end
