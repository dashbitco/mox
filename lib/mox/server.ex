defmodule Mox.Server do
  @moduledoc false

  alias NimbleOwnership, as: N

  @timeout 30000
  @this {:global, __MODULE__}

  # API

  def child_spec(_options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link_ownership, []}}
  end

  def start_link_ownership do
    case N.start_link(name: @this) do
      {:error, {:already_started, _}} -> :ignore
      other -> other
    end
  end

  def add_expectation(owner_pid, {mock, _, _} = key, expectation) do
    # First, make sure that the owner_pid is either the owner or that the mock
    # isn't owned yet. Otherwise, return an error.
    case N.fetch_owner(@this, [owner_pid], mock, @timeout) do
      {tag, ^owner_pid} when tag in [:ok, :global_owner] -> :ok
      {:global_owner, other_owner} -> throw({:error, {:not_global_owner, other_owner}})
      {:ok, other_owner} -> throw({:error, {:currently_allowed, other_owner}})
      :error -> :ok
    end

    update_fun = fn
      nil ->
        {nil, %{key => expectation}}

      %{} = expectations ->
        {nil, Map.update(expectations, key, expectation, &merge_expectation(&1, expectation))}
    end

    {:ok, _} = N.get_and_update(@this, owner_pid, mock, update_fun, @timeout)
    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  def init_mock(owner_pid, mock) do
    {:ok, _} = N.get_and_update(@this, owner_pid, mock, fn nil -> {nil, %{}} end, @timeout)
    :ok
  end

  def fetch_fun_to_dispatch(caller_pids, {mock, _, _} = key) do
    # If the mock doesn't have an owner, it can't have expectations so we return :no_expectation.
    owner_pid =
      case N.fetch_owner(@this, caller_pids, mock, @timeout) do
        {tag, owner_pid} when tag in [:global_owner, :ok] -> owner_pid
        :error -> throw(:no_expectation)
      end

    parent = self()

    update_fun = fn expectations ->
      case expectations[key] do
        nil ->
          {:no_expectation, expectations}

        {total, [], nil} ->
          {{:out_of_expectations, total}, expectations}

        {_, [], stub} ->
          {{ok_or_remote(parent), stub}, expectations}

        {total, [call | calls], stub} ->
          new_expectations = put_in(expectations[key], {total, calls, stub})
          {{ok_or_remote(parent), call}, new_expectations}
      end
    end

    {:ok, return} = N.get_and_update(@this, owner_pid, mock, update_fun, @timeout)
    return
  catch
    return -> return
  end

  def verify(owner_pid, for) do
    all_expectations = N.get_owned(@this, owner_pid, _default = %{}, @timeout)

    _pending =
      for {_mock, expected_funs} <- all_expectations,
          {{module, _, _} = key, {count, [_ | _] = calls, _stub}} <- expected_funs,
          module == for or for == :all do
        {key, count, length(calls)}
      end
  end

  def allow(mock, owner_pid, pid_or_function) do
    N.allow(@this, owner_pid, pid_or_function, mock, @timeout)
  end

  def set_mode(_owner_pid, :private), do: N.set_mode_to_private(@this)
  def set_mode(owner_pid, :global), do: N.set_mode_to_shared(@this, owner_pid)

  # Helper functions

  defp merge_expectation({current_n, current_calls, _current_stub}, {n, calls, stub}) do
    {current_n + n, current_calls ++ calls, stub}
  end

  defp ok_or_remote(source) when node(source) == node(), do: :ok
  defp ok_or_remote(_source), do: :remote
end
