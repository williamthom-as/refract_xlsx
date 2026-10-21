fixtures
========

xlsx files made by libreoffice from the flat ods sources in source so the reader is tested on files the plugin did not write

make them again with

    soffice --headless --convert-to xlsx --outdir test/fixtures test/fixtures/source/*.fods

file          sheets                                  covers
types.xlsx    Data                                    text numbers ids dates date times times booleans blank cells formulas
sheets.xlsx   Summary Line items lookup hidden        a cover sheet then a table sheet a merged title cell a hidden sheet
offset.xlsx   names ages                              complex joins as a workbook tables offset below a total
months.xlsx   Jul Aug Sep Notes                       one aws bill shape in three sheets with numeric ids and a notes sheet
golden/complex_joins/expected.csv                     copied from refract core golden complex_joins

libreoffice quirks
==================

custom date formats are written with escaped separators like yyyy\-mm\-dd so the plugin adds format rules for them
booleans need a boolean number style in the source or they are written as plain numbers
times are stored as a fraction of a day and read back as a date time on the base date 1899-12-30 so the plugin turns those into times
