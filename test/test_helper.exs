excludes =
  if Version.match?(System.version(), ">= 1.8.0") do
    []
  else
    [:requires_caller_tracking]
  end

ExUnit.start(exclude: excludes)
