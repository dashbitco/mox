# Changelog

## v1.0.1 (2020-10-15)

### Bug fix

  * Fix race condition for when the test process terminates and a new one is started before the DOWN message is processed

## v1.0.0 (2020-09-25)

### Enhancements

  * Add `@behaviour` attribute to Mox modules

## v0.5.2 (2020-02-20)

### Enhancements

  * Warn if global is used with async mode
  * Fix compilation warnings

## v0.5.1 (2019-05-24)

### Enhancements

  * Add `:skip_optional_callbacks` option to `defmock/2` that allows you to optionally skip the definition of optional callbacks.
  * Include arguments in `UnexpectedCallError` exceptions

## v0.5.0 (2019-02-03)

### Enhancements

  * Use `$callers` to automatically use expectations defined in the calling process (`$callers` is set automatically by tasks in Elixir v1.8 onwards)
  * Creating an allowance in global mode is now a no-op for convenience
  * Support registered process names for allowances
