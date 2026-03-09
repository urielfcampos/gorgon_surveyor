defmodule GorgonSurvey.LogParserTest do
  use ExUnit.Case, async: true

  alias GorgonSurvey.LogParser

  describe "parse_line/1" do
    test "parses survey with west and north" do
      line = "The Good Metal Slab is 815m west and 1441m north."
      assert {:survey, %{name: "Good Metal Slab", dx: -815, dy: 1441}} = LogParser.parse_line(line)
    end

    test "parses survey with east and south" do
      line = "The Fine Gravel Patch is 200m east and 300m south."
      assert {:survey, %{name: "Fine Gravel Patch", dx: 200, dy: -300}} = LogParser.parse_line(line)
    end

    test "parses motherlode distance" do
      line = "The treasure is 1000 meters away"
      assert {:motherlode, %{meters: 1000}} = LogParser.parse_line(line)
    end

    test "parses survey collected" do
      line = "You collected the survey reward"
      assert :survey_collected = LogParser.parse_line(line)
    end

    test "returns nil for unrelated lines" do
      assert nil == LogParser.parse_line("Hello world")
      assert nil == LogParser.parse_line("")
    end

    test "motherlode checked before survey to avoid false match" do
      line = "The treasure is 500 meters away"
      assert {:motherlode, %{meters: 500}} = LogParser.parse_line(line)
    end
  end
end
