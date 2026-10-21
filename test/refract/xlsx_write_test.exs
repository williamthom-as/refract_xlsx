defmodule Refract.XLSXWriteTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.XLSX

  defp cells!(path, opts \\ []) do
    {:ok, raw} = XLSX.open(path, opts)

    Enum.to_list(raw)
  end

  describe "write/3" do
    test "native values come back with their types", %{tmp_dir: dir} do
      path = Path.join(dir, "types.xlsx")

      rows = [
        %{
          "text" => "007",
          "decimal" => Decimal.new("3.5"),
          "integer" => 7,
          "float" => 1.5,
          "day" => ~D[2026-10-21],
          "at" => ~N[2026-10-21 09:30:00],
          "flag" => true,
          "blank" => nil
        }
      ]

      header = ["text", "decimal", "integer", "float", "day", "at", "flag", "blank"]

      assert :ok = XLSX.write(rows, path, header: header)

      assert cells!(path) == [
               header,
               [
                 "007",
                 Decimal.new("3.5"),
                 Decimal.new("7"),
                 Decimal.new("1.5"),
                 ~D[2026-10-21],
                 ~N[2026-10-21 09:30:00],
                 true,
                 ""
               ]
             ]
    end

    test "times are written as text", %{tmp_dir: dir} do
      path = Path.join(dir, "times.xlsx")

      assert :ok = XLSX.write([%{"time" => ~T[09:30:00]}], path)
      assert cells!(path) == [["time"], ["09:30:00"]]
    end

    test "sheet: names the sheet", %{tmp_dir: dir} do
      path = Path.join(dir, "report.xlsx")

      assert :ok = XLSX.write([%{"id" => "1"}], path, sheet: "Report")
      assert {:ok, %{sheets: ["Report"]}} = XLSX.facts(path, [])
    end

    test "no rows and no header writes an empty sheet", %{tmp_dir: dir} do
      path = Path.join(dir, "empty.xlsx")

      assert :ok = XLSX.write([], path)
      assert {:ok, rows} = XLSX.stream(path)
      assert Enum.to_list(rows) == []
    end

    test "no rows with a header writes the header", %{tmp_dir: dir} do
      path = Path.join(dir, "header.xlsx")

      assert :ok = XLSX.write([], path, header: ["id", "name"])
      assert cells!(path) == [["id", "name"]]
    end

    test "rows are written lazily", %{tmp_dir: dir} do
      path = Path.join(dir, "many.xlsx")
      rows = Stream.map(1..5_000, &%{"id" => &1})

      assert :ok = XLSX.write(rows, path)
      assert length(cells!(path)) == 5_001
    end

    test "unknown options raise", %{tmp_dir: dir} do
      assert_raise ArgumentError, ~r/colour/, fn ->
        XLSX.write([%{"id" => "1"}], Path.join(dir, "x.xlsx"), colour: :blue)
      end
    end

    test "a sheet name that is not a string raises", %{tmp_dir: dir} do
      assert_raise ArgumentError, ~r/sheet/, fn ->
        XLSX.write([%{"id" => "1"}], Path.join(dir, "x.xlsx"), sheet: 1)
      end
    end
  end

  describe "write/3 opened by libreoffice" do
    @describetag :libreoffice

    test "libreoffice reads the values back", %{tmp_dir: dir} do
      path = Path.join(dir, "report.xlsx")

      rows = [
        %{"id" => "007", "total" => Decimal.new("3.5"), "day" => ~D[2026-10-21]},
        %{"id" => "8", "total" => 12, "day" => ~D[2026-10-22]}
      ]

      :ok = XLSX.write(rows, path, header: ["id", "total", "day"])

      {_output, 0} =
        System.cmd("soffice", ["--headless", "--convert-to", "csv", "--outdir", dir, path],
          stderr_to_stdout: true
        )

      assert File.read!(Path.join(dir, "report.csv")) ==
               "id,total,day\n007,3.5,2026-10-21\n8,12,2026-10-22\n"
    end
  end
end
