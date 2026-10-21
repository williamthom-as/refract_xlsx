defmodule Refract.Conformance.XLSXWriterTest do
  use Refract.Test.WriterCase,
    writer: Refract.XLSX,
    read: fn path ->
      {:ok, raw} = Refract.XLSX.open(path, [])

      Enum.to_list(raw)
    end
end
