defmodule Tsundoku.DomainMutexTest do
  use ExUnit.Case, async: false

  alias Tsundoku.DomainMutex

  test "second acquire of the same domain reports :busy" do
    domain = unique("example.com")

    parent = self()

    holder =
      spawn(fn ->
        assert :ok = DomainMutex.try_acquire(domain)
        send(parent, :acquired)
        receive do: (:release -> :ok)
        DomainMutex.release(domain)
      end)

    assert_receive :acquired, 500
    assert :busy = DomainMutex.try_acquire(domain)
    send(holder, :release)

    # Give the GenServer time to process the release.
    Process.sleep(20)
    assert :ok = DomainMutex.try_acquire(domain)
    DomainMutex.release(domain)
  end

  test "different domains do not block each other" do
    a = unique("a.com")
    b = unique("b.com")

    assert :ok = DomainMutex.try_acquire(a)
    assert :ok = DomainMutex.try_acquire(b)

    DomainMutex.release(a)
    DomainMutex.release(b)
  end

  test "exit of holder releases the lock" do
    domain = unique("dead.com")
    parent = self()

    holder =
      spawn(fn ->
        assert :ok = DomainMutex.try_acquire(domain)
        send(parent, :acquired)
        # exit without releasing
      end)

    assert_receive :acquired, 500

    # Wait for the DOWN to be processed.
    ref = Process.monitor(holder)
    assert_receive {:DOWN, ^ref, :process, _, _}, 500
    Process.sleep(20)

    assert :ok = DomainMutex.try_acquire(domain)
    DomainMutex.release(domain)
  end

  test "nil / empty domains are not serialized" do
    assert :ok = DomainMutex.try_acquire(nil)
    assert :ok = DomainMutex.try_acquire(nil)
    assert :ok = DomainMutex.try_acquire("")
    assert :ok = DomainMutex.try_acquire("")
  end

  defp unique(name), do: "#{System.unique_integer([:positive])}-#{name}"
end
