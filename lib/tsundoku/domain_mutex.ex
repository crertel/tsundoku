defmodule Tsundoku.DomainMutex do
  @moduledoc """
  In-process per-domain mutex. Used by the metadata workers to keep
  multiple parallel fetches from hitting the same host at the same
  time, regardless of queue concurrency.

  Acquire returns `:ok` or `:busy`; callers that get `:busy` should
  snooze and try again later. The lock is released when the owner
  process exits (via `Process.monitor/1`) even if it forgets to call
  `release/1` explicitly.

  Single-node only.
  """

  use GenServer

  @name __MODULE__

  ## Client

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: @name)

  @doc """
  Try to take the lock for `domain`. Returns `:ok` if acquired or
  `:busy` if another caller holds it. A `nil` or empty domain is a
  no-op that returns `:ok` (we don't serialize sites without a domain).
  """
  def try_acquire(domain) when is_binary(domain) and domain != "",
    do: GenServer.call(@name, {:acquire, domain, self()})

  def try_acquire(_), do: :ok

  @doc "Release the lock for `domain`. Safe to call even if not held."
  def release(domain) when is_binary(domain) and domain != "",
    do: GenServer.cast(@name, {:release, domain, self()})

  def release(_), do: :ok

  ## Server

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:acquire, domain, owner}, _from, state) do
    case Map.get(state, domain) do
      nil ->
        ref = Process.monitor(owner)
        {:reply, :ok, Map.put(state, domain, {owner, ref})}

      _ ->
        {:reply, :busy, state}
    end
  end

  @impl true
  def handle_cast({:release, domain, owner}, state) do
    case Map.get(state, domain) do
      {^owner, ref} ->
        Process.demonitor(ref, [:flush])
        {:noreply, Map.delete(state, domain)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    new_state =
      state
      |> Enum.reject(fn {_, {_, owner_ref}} -> owner_ref == ref end)
      |> Map.new()

    {:noreply, new_state}
  end
end
