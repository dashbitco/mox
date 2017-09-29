defmodule Mox.Server do
  @moduledoc false

  use GenServer

  # Public API

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def add_expectation(owner_pid, key, {n, calls, stub}) do
    GenServer.call(__MODULE__, {:add_expectation, owner_pid, key, {n, calls, stub}})
  end

  def get_expectation(owner_pid, key) do
    GenServer.call(__MODULE__, {:get_expectation, owner_pid, key})
  end

  def get_fun_to_call(owner_pid, key) do
    GenServer.call(__MODULE__, {:get_fun_to_call, owner_pid, key})
  end

  def keys(owner_pid) do
    GenServer.call(__MODULE__, {:keys, owner_pid})
  end

  # Callbacks

  def handle_call({:add_expectation, owner_pid, key, {n, calls, stub}}, _from, state) do
    new_state = state
                |> maybe_add_pid(owner_pid)
                |> update_in([owner_pid, key], &(do_add_expectation(&1, {n, calls, stub})))

    {:reply, :ok, new_state}
  end

  def handle_call({:get_expectation, owner_pid, key}, _from, state) do
    {:reply, state[owner_pid][key], state}
  end

  def handle_call({:get_fun_to_call, owner_pid, key}, _from, state) do
    case Map.get(state, owner_pid, %{})[key] do
      nil ->
        {:reply, :no_expectation, state}

      {_, [], stub} when not is_nil(stub) ->
        {:reply, {:ok, stub}, state}

      {total, calls, stub} ->
        new_state = put_in(state, [owner_pid, key], {total, drop_call(calls), stub})
        {:reply, block_or_allow_next_call(total, calls), new_state}
    end
  end

  def handle_call({:keys, owner_pid}, _from, state) do
    keys = state
           |> Map.get(owner_pid, %{})
           |> Map.keys()

    {:reply, keys, state}
  end

  # Helper functions

  defp drop_call([]), do: []
  defp drop_call([_ | tail]), do: tail

  defp maybe_add_pid(state, pid) do
    case state[pid] do
      nil -> Map.put_new(state, pid, %{})
      _ -> state
    end
  end

  defp do_add_expectation(nil, {n, calls, stub}), do: {n, calls, stub}
  defp do_add_expectation({current_n, current_calls, stub}, {n, calls, nil}) do
    {current_n + n, current_calls ++ calls, stub}
  end
  defp do_add_expectation({current_n, current_calls, _current_stub}, {0, [], stub}) do
    {current_n, current_calls, stub}
  end

  defp block_or_allow_next_call(count, []), do: {:out_of_expectations, count}
  defp block_or_allow_next_call(_count, [fun_to_call | _]), do: {:ok, fun_to_call}
end
