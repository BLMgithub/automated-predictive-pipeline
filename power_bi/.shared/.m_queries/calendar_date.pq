let
  SourceRecent = predictions_nextweek,
  SourceMin = predictions_evaluation,
  RecentDate = Date.From(List.Max(SourceRecent[week_start])),
  MinDate = Date.From(List.Min(SourceMin[week_start])),

  // List dates
  StartDate = MinDate,
  EndDate = RecentDate,
  CalendarList = List.Dates(StartDate, Duration.Days(EndDate - StartDate) + 1, #duration(1, 0 ,0 ,0)),

  // Convert to table
  #"Converted to Table" = Table.FromList(CalendarList, Splitter.SplitByNothing(), {"Date"}, null, ExtraValues.Error),
  #"Changed Type" = Table.TransformColumnTypes(#"Converted to Table", {{"Date", type date}}),

  // Date columns
  #"Added Year" = Table.AddColumn(#"Changed Type", "Year", each Date.Year([Date]), Int64.Type),
  #"Added Month" = Table.AddColumn(#"Added Year", "Month", each Date.Month([Date]), Int64.Type),
  #"Added Month Name" = Table.AddColumn(#"Added Month", "Month Name", each Date.MonthName([Date]), type text),
  // #"Added Weekly Number" = Table.AddColumn(#"Added Month", "Week Number", )
  #"Added Week Start Date" = Table.AddColumn(#"Added Month Name", "Week Start Date", each Date.StartOfWeek([Date], Day.Monday), type date)
in
  #"Added Week Start Date"