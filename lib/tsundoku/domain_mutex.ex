defmodule Tsundoku.DomainMutex do
  @moduledoc """
  In-process per-domain mutex. Used by the metadata workers to keep
  multiple parallel fetches from hitting the same host at the same
  time, regardless of queue concurrency.

  Acquire returns `:ok` or `:busy`; callers that get `:busy` should
  snooze and try again later. The lock is released when the owner
  process exits (via `Process.monitor/1`) even if it forgets to call
  `release/1` explicitly.

  A release can ask for a cooldown, during which the domain stays busy
  for everyone. That is how the crawler spaces out requests to one host.

  Single-node only.
  """

  use GenServer

  @name __MODULE__

  ## Client

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: @name)

  @doc """
  Try to take the lock for `domain`. Returns `:ok` if acquired or
  `:busy` if another caller holds it or it is cooling down. A `nil` or
  empty domain is a no-op that returns `:ok` (we don't serialize sites
  without a domain).
  """
  def try_acquire(domain) when is_binary(domain) and domain != "",
    do: GenServer.call(@name, {:acquire, domain, self()})

  def try_acquire(_), do: :ok

  @doc """
  Release the lock for `domain`. Safe to call even if not held. With a
  `cooldown_ms` above zero, the domain stays busy for that long after
  the release.
  """
  def release(domain, cooldown_ms \\ 0)

  def release(domain, cooldown_ms) when is_binary(domain) and domain != "",
    do: GenServer.cast(@name, {:release, domain, self(), cooldown_ms})

  def release(_, _), do: :ok

  ## Server
  #
  # State maps a domain to `{:held, owner, monitor_ref}` or
  # `{:cooldown, token}`. The token ties a cooldown to the timer that
  # ends it, so a stale timer can't clear a newer entry.

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:acquire, domain, owner}, _from, state) do
    case Map.get(state, domain) do
      nil ->
        ref = Process.monitor(owner)
        {:reply, :ok, Map.put(state, domain, {:held, owner, ref})}

      _ ->
        {:reply, :busy, state}
    end
  end

  @impl true
  def handle_cast({:release, domain, owner, cooldown_ms}, state) do
    case Map.get(state, domain) do
      {:held, ^owner, ref} ->
        Process.demonitor(ref, [:flush])
        {:noreply, start_cooldown(state, domain, cooldown_ms)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    new_state =
      state
      |> Enum.reject(fn
        {_domain, {:held, _owner, owner_ref}} -> owner_ref == ref
        _ -> false
      end)
      |> Map.new()

    {:noreply, new_state}
  end

  def handle_info({:cooldown_over, domain, token}, state) do
    case Map.get(state, domain) do
      {:cooldown, ^token} -> {:noreply, Map.delete(state, domain)}
      _ -> {:noreply, state}
    end
  end

  defp start_cooldown(state, domain, cooldown_ms)
       when is_integer(cooldown_ms) and cooldown_ms > 0 do
    token = make_ref()
    Process.send_after(self(), {:cooldown_over, domain, token}, cooldown_ms)
    Map.put(state, domain, {:cooldown, token})
  end

  defp start_cooldown(state, domain, _cooldown_ms), do: Map.delete(state, domain)
end
