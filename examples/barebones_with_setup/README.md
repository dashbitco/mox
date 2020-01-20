# MoxExample

## Description

This example is a barebones example of how to use [Mox](https://github.com/dashbitco/mox) and how to configure it during testing.

## How

Run `mix test` and you'll see a mocked HTTP call tested without making the HTTP call.

Run `iex -S mix` and then `MoxExample.post_name("Mox")` and you'll see the HTTP request go through!
