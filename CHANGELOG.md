# Changelog

## v0.5.1 (2019-05-24)

### Enhancements

  * Add `:skip_optional_callbacks` option to `defmock/2` that allows you to optionally skip the definition of optional callbacks.
  * Include arguments in `UnexpectedCallError` exceptions

## v0.5.0 (2019-02-03)

### Enhancements

  * Use `$callers` to automatically use expectations defined in the calling process (`$callers` is set automatically by tasks in Elixir v1.8 onwards)
  * Creating an allowance in global mode is now a no-op for convenience
  * Support registered process names for allowances
