defmodule Refract.XLSXTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify.Result
  alias Refract.Grid
  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX

  @fixtures Path.expand("../fixtures", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  defp cells!(source, opts \\ []) do
    {:ok, raw} = XLSX.open(source, opts)

    Enum.to_list(raw)
  end

  defp invoice do
    Shape.new(
      name: "invoice",
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "item" => ["item"], "total" => ["total"]}],
          row: [match: %{"sku" => :integer, "total" => :number}]
        )
    )
  end

  describe "open/2 sheets" do
    test "reads the first visible sheet by default" do
      assert cells!(fixture("sheets.xlsx")) == [
               ["Tax Invoice", ""],
               ["total", Decimal.new("12.5")]
             ]
    end

    test "sheet: picks a sheet by name" do
      assert [["sku", "item", "total"] | _rows] =
               cells!(fixture("sheets.xlsx"), sheet: "Line items")
    end

    test "sheet: picks a sheet by position, counting from one" do
      assert [["sku", "item", "total"] | _rows] = cells!(fixture("sheets.xlsx"), sheet: 2)
    end

    test "a hidden sheet is read when named" do
      assert [["code", "rate"], ["a", rate]] = cells!(fixture("sheets.xlsx"), sheet: "lookup")
      assert rate == Decimal.new("1")
    end

    test "hidden sheets do not count as positions unless hidden: true" do
      assert {:error, {:unknown_sheet, 3}} = XLSX.open(fixture("sheets.xlsx"), sheet: 3)
      assert [["code", "rate"] | _rows] = cells!(fixture("sheets.xlsx"), sheet: 3, hidden: true)
    end

    test "an unknown sheet is an error" do
      assert {:error, {:unknown_sheet, "Nope"}} = XLSX.open(fixture("sheets.xlsx"), sheet: "Nope")
    end

    test "a sheet that is not a name or a position raises" do
      for sheet <- [0, :first, 1.5] do
        assert_raise ArgumentError, ~r/sheet/, fn ->
          XLSX.open(fixture("sheets.xlsx"), sheet: sheet)
        end
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        XLSX.open(fixture("sheets.xlsx"), colour: :blue)
      end
    end
  end

  describe "open/2 cells" do
    test "cells come back as native values" do
      assert cells!(fixture("types.xlsx")) == [
               ["name", "amount", "account", "day", "at", "time", "flag", "blank", "double"],
               [
                 "alice",
                 Decimal.new("3.5"),
                 Decimal.new("123456789012"),
                 ~D[2026-10-21],
                 ~N[2026-10-21 09:30:00],
                 ~T[09:30:00],
                 true,
                 "",
                 Decimal.new("7")
               ],
               [
                 "bob",
                 Decimal.new("-2.25"),
                 Decimal.new("7"),
                 ~D[2026-01-02],
                 ~N[2026-01-02 17:05:30],
                 ~T[17:05:30],
                 false,
                 "",
                 Decimal.new("-4.5")
               ]
             ]
    end

    test "a merged cell keeps its value in its first cell" do
      assert [["Tax Invoice", ""] | _rows] = cells!(fixture("sheets.xlsx"))
    end
  end

  describe "open/2 sources" do
    test "a workbook in a string" do
      assert [["Tax Invoice", ""] | _rows] = cells!({:string, File.read!(fixture("sheets.xlsx"))})
    end

    test "a workbook in a stream of chunks" do
      chunks = fixture("sheets.xlsx") |> File.stream!(1024) |> Enum.to_list()

      assert [["Tax Invoice", ""] | _rows] = cells!({:stream, chunks})
    end

    test "a missing file is an error" do
      assert {:error, :enoent} = XLSX.open(fixture("missing.xlsx"), [])
    end

    test "a file that is not a workbook is an error", %{tmp_dir: dir} do
      path = Path.join(dir, "notes.xlsx")
      File.write!(path, "id,name\n1,alice\n")

      assert {:error, {:invalid_xlsx, _message}} = XLSX.open(path, [])
    end

    test "an unsupported source is an error" do
      assert {:error, {:unsupported_source, :bills}} = XLSX.open(:bills, [])
    end
  end

  describe "facts/2" do
    test "name the sheet read, the visible sheets and the hidden ones" do
      assert {:ok, %{sheet: "Summary", sheets: ["Summary", "Line items"], hidden: ["lookup"]}} =
               XLSX.facts(fixture("sheets.xlsx"), [])

      assert {:ok, %{sheet: "Line items"}} = XLSX.facts(fixture("sheets.xlsx"), sheet: 2)
    end
  end

  describe "sheets/2" do
    test "lists the visible sheets" do
      assert {:ok, ["Summary", "Line items"]} = XLSX.sheets(fixture("sheets.xlsx"), [])
    end

    test "hidden: true lists every sheet" do
      assert {:ok, ["Summary", "Line items", "lookup"]} =
               XLSX.sheets(fixture("sheets.xlsx"), hidden: true)
    end

    test "sheet: narrows it to that sheet, by name or position" do
      assert {:ok, ["Line items"]} = XLSX.sheets(fixture("sheets.xlsx"), sheet: "Line items")
      assert {:ok, ["Line items"]} = XLSX.sheets(fixture("sheets.xlsx"), sheet: 2)
    end

    test "an unknown sheet or a missing file is an error" do
      assert {:error, {:unknown_sheet, "Nope"}} =
               XLSX.sheets(fixture("sheets.xlsx"), sheet: "Nope")

      assert {:error, :enoent} = XLSX.sheets(fixture("missing.xlsx"), [])
    end
  end

  describe "classify_sheets/3" do
    defp aws_bill do
      Shape.new(
        name: "aws_bill",
        spec:
          Table.spec(
            header: [columns: %{"account" => ["account"], "cost" => ["cost"]}],
            row: [match: %{"account" => ~r/^\d{12}$/, "cost" => :number}]
          )
      )
    end

    defp verdicts(sheets) do
      for {sheet, {:ok, %Result{verdict: verdict, shape: shape}}} <- sheets,
          do: {sheet, verdict, verdict == :match && shape.name}
    end

    test "classifies every visible sheet of a workbook" do
      assert {:ok, sheets} = XLSX.classify_sheets(fixture("months.xlsx"), [aws_bill()])

      assert verdicts(sheets) == [
               {"Jul", :match, "aws_bill"},
               {"Aug", :match, "aws_bill"},
               {"Sep", :match, "aws_bill"},
               {"Notes", :unknown, false}
             ]
    end

    test "each result names its sheet" do
      assert {:ok, sheets} = XLSX.classify_sheets(fixture("sheets.xlsx"), [invoice()])

      for {sheet, {:ok, result}} <- sheets, do: assert(result.file.format.sheet == sheet)
    end

    test "a cover sheet does not hide the table sheet" do
      assert {:ok, sheets} = XLSX.classify_sheets(fixture("sheets.xlsx"), [invoice()])

      assert verdicts(sheets) == [{"Summary", :unknown, false}, {"Line items", :match, "invoice"}]
    end

    test "hidden: true includes hidden sheets, sheet: narrows to one" do
      assert {:ok, [_summary, _items, {"lookup", {:ok, _result}}]} =
               XLSX.classify_sheets(fixture("sheets.xlsx"), [invoice()], hidden: true)

      assert {:ok, [{"Aug", {:ok, %Result{verdict: :match}}}]} =
               XLSX.classify_sheets(fixture("months.xlsx"), [aws_bill()], sheet: "Aug")
    end

    test "classify options apply to every sheet" do
      assert {:ok, sheets} =
               XLSX.classify_sheets(fixture("months.xlsx"), [aws_bill()], within: 0)

      assert Enum.all?(sheets, &match?({_sheet, {:ok, %Result{verdict: :unknown}}}, &1))
    end

    test "a workbook that cannot be read is an error" do
      assert {:error, :enoent} = XLSX.classify_sheets(fixture("missing.xlsx"), [invoice()])
    end
  end

  describe "through Refract.Reader" do
    test "extensions are xlsx and xlsm" do
      assert XLSX.extensions() == ["xlsx", "xlsm"]
    end

    test "locate finds a table below a total" do
      spec =
        Table.spec(
          header: [
            columns: %{
              "id" => ["id"],
              "first_name" => ["first_name"],
              "last_name" => ["last_name"]
            }
          ]
        )

      assert {:ok, table} = XLSX.locate(fixture("offset.xlsx"), spec, sheet: "names")

      assert Enum.to_list(table.rows) == [
               %{"id" => Decimal.new("1"), "first_name" => "fred", "last_name" => "jones"},
               %{"id" => Decimal.new("2"), "first_name" => "john", "last_name" => "smith"}
             ]
    end

    test "load gives a grid with the value beside a label" do
      assert {:ok, grid} = XLSX.load(fixture("offset.xlsx"), sheet: "ages")
      assert Grid.value(grid, label: "total") == Decimal.new("20")
    end

    test "classify reads the sheet given and names it in the result" do
      assert {:ok, %Result{verdict: :match} = result} =
               XLSX.classify(fixture("sheets.xlsx"), [invoice()], sheet: "Line items")

      assert result.file.format.sheet == "Line items"
    end

    test "classify without sheet: reads the first visible sheet" do
      assert {:ok, %Result{verdict: :unknown} = result} =
               XLSX.classify(fixture("sheets.xlsx"), [invoice()])

      assert result.file.format.sheet == "Summary"
    end
  end
end
