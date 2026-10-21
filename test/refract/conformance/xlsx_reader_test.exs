defmodule Refract.Conformance.XLSXReaderTest do
  use Refract.Test.ReaderCase,
    reader: Refract.XLSX,
    build: fn rows, dir ->
      path = Path.join(dir, "source.xlsx")

      content = if rows == [], do: [[]], else: rows

      workbook =
        "refract"
        |> Exceed.Workbook.new()
        |> Exceed.Workbook.add_worksheet(Exceed.Worksheet.new("Sheet1", nil, content))

      File.write!(path, workbook |> Exceed.stream!() |> Enum.to_list())

      path
    end
end
