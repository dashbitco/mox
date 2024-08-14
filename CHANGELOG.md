# Changelog

## v1.2.0 (2024-08-04)

This release is mostly about reducing the complexity of Mox by switching its ownership implementation to use the new [nimble_ownership library](https://github.com/dashbitco/nimble_ownership).

### Enhancements

  * Add `Mox.deny/3`.
  * Optimize `Mox.stub_with/2`.

## v1.1.0 (2023-09-20)

### Enhancements

  * Support testing in a cluster
  * Support a function to retrieve the PID to allow in `Mox.allow/3`

## v1.0.2 (2022-05-30)

### Bug fix

  * Use `Code.ensure_compiled!` to support better integration with the Elixir compiler

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
