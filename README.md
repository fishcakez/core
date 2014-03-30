# Core
Library for implementing OTP processes natively in Elixir.

Provides utility functions and macros to implement 100% OTP compliant
processes with 100%\* compatibility with all Erlang/OTP modules and tools.

\* The getting and replacing of process state debug functions will not
behave idenitically with `:sys` until 17.0 final is released.

# Installing
```
git clone https://github.com/fishcakez/core.git
cd core
mix do deps.get, docs, compile
```

# Hello World
Start a process that prints "Hello World" to `:stdio`.
```elixir
defmodule HelloWorld do

  use Core.Behaviour

  def start_link(), do: Core.start_link(__MODULE__, nil)

  def init(_parent, _debug, _args) do
    IO.puts("Hello World")
    # Core.init_ack/0 will cause start_link/0 to return { :ok, self() }. If this
    # function is never called start_link will block until this process exits.
    Core.init_ack()
    exit(:normal)
  end

end
```

# Features
* Call processes (including Erlang/OTP's `:gen_server` processes) with
  very detailed exception messages.
* Asynchronous and synchronous process initiation (with name registration).
* Automatic logging of un-rescued exceptions.
* System calls that work with any OTP compliant process.
* Receive macro to handle system messages.
* Supports progressive enhancement of OTP features: system message
  automatically handled until you want to change the default behaviour.

# Call a :gen\_server registered as :server
```elixir
Core.call(:"$gen_call", :server, request, timeout)
```
If `:server` does not exist:
```
** (Core.CallError) $gen_call to server failed: no process associated with that name
```

# Basic Ping Server
Starts a process that can be pinged.
```elixir
defmodule PingPong do

  use Core.Behaviour

  @spec ping(Core.t) :: :pong
  def ping(process), do: Core.call(process, __MODULE__, :ping, 5000)

  @spec count(Core.t) :: non_neg_integer
  def count(process), do: Core.call(process, __MODULE__, :count, 5000)

  @spec close(Core.t) :: :ok
  def close(process), do: Core.call(process, __MODULE__, :close, 5000)

  @spec start_link() :: { :ok, pid }
  def start_link() do
    Core.start_link(__MODULE__, nil)
  end

  # Core api

  def init(_parent, _args) do
    Core.init_ack()
    loop(0)
  end

  ## Internal

  defp loop(count) do
    receive do
      { __MODULE__, from, :ping } ->
        Core.reply(from, :pong)
        loop(count + 1)
      { __MODULE__, from, :count } ->
        Core.reply(from, count)
        loop(count)
      { __MODULE__, from, :close } ->
        Core.reply(from, :ok)
        terminate(:normal)
    end
  end

  defp terminate(reason) do
    exit(reason)
  end

end
```

# Advanced Ping Server
Starts a process that can be pinged, live debugged and live code
upgraded.

For example `Core.Sys.set_state(pid, 0)` will reset the `count` to `0`.
```elixir

defmodule PingPong do

  use Core.Behaviour
  use Core.Sys.Behaviour

  @spec ping(Core.t) :: :pong
  def ping(process), do: Core.call(process, __MODULE__, :ping, 5000)

  @spec count(Core.t) :: non_neg_integer
  def count(process), do: Core.call(process, __MODULE__, :count, 5000)

  @spec close(Core.t) :: :ok
  def close(process), do: Core.call(process, __MODULE__, :close, 5000)

  # die/1 will print alot of information because the exit reason is abnormal.
  @spec die(Core.t) :: :ok
  def die(process), do: Core.call(process, __MODULE__, :die, 5000)

  @spec start_link() :: { :ok, pid }
  def start_link() do
    Core.start_link(__MODULE__, nil)
  end

  ## Core api

  def init(parent, _args) do
    Core.init_ack()
    loop(0, parent)
  end

  ## Core.Sys (minimal) api

  def system_continue(count, parent), do: loop(count, parent)

  def system_terminate(count, parent, reason) do
    terminate(count, parent, reason)
  end

  ## Internal

  defp loop(count, parent) do
    Core.Sys.receive(__MODULE__, count, parent) do
      { __MODULE__, from, :ping } ->
        Core.reply(from, :pong)
        loop(count + 1, parent)
      { __MODULE__, from, :count } ->
        Core.reply(from, count)
        loop(count, parent)
      { __MODULE__, from, :close } ->
        Core.reply(from, :ok)
        terminate(count, parent, :normal)
      { __MODULE__, from, :die } ->
        Core.reply(from, :ok)
        terminate(count, parent, :die)
    end
  end

  defp terminate(count, parent, reason) do
    Core.stop(__MODULE__, count, parent, reason)
  end

end
```





