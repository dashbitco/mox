Mox.defmock(CalcMock, for: Calculator)
Mox.defmock(SciCalcMock, for: [Calculator, ScientificCalculator])

Mox.defmock(MyMockWithoutModuledoc, for: Calculator)
Mox.defmock(MyMockWithFalseModuledoc, for: Calculator, moduledoc: false)
Mox.defmock(MyMockWithStringModuledoc, for: Calculator, moduledoc: "hello world")
