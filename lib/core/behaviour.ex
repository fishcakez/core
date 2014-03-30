defmodule Core.Behaviour do
  @moduledoc """
  This module is a convenience module for adding the `Core` behaviour.

  ## Examples

      defmodule Core.HelloWorld do

        use Core.Behaviour

        @spec start_link() :: { :ok, pid }
        def start_link(), do: Core.start_link(__MODULE__, nil)

        def init(_parent, nil) do
          Core.init_ack()
          IO.puts("Hello World!")
        end

      end

      defmodule Core.Fn do

        use Core.Behaviour

        @spec start_link((() -> any)) :: { :ok, pid }
        def start_link(fun), do: Core.start_link(__MODULE__, fun)

        @spec spawn_link((() -> any)) :: pid
        def spawn_link(fun), do: Core.spawn_link(__MODULE__, fun)

        def init(parent, fun) when is_function(fun, 0) do
          Core.init_ack()
          try do
            fun.()
          rescue
            exception ->
              reason = { exception, System.stacktrace() }
              Core.stop(__MODULE__, fun, parent, reason)
          catch
            :throw, value ->
              exception = Core.UncaughtThrowError[actual: value]
              reason = { exception, System.stacktrace() }
              Core.stop(__MODULE__, fun, parent, reason)
          end
        end

      end

      defmodule Core.PingPong do

        @spec ping(Core.t) :: :pong
        def ping(process), do: Core.call(process, __MODULE__, :ping, 5000)

        @spec count(Core.t) :: non_neg_integer
        def count(process), do: Core.call(process, __MODULE__, :count, 5000)

        @spec close(Core.t) :: :ok
        def close(process), do: Core.call(process, __MODULE__, :close, 5000)

        @spec start_link() :: { :ok, pid }
        def start_link(), do: Core.start_link(__MODULE__, nil)

        def init(_parent, _nil) do
          Core.init_ack()
          loop(0)
        end

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
              terminate(count)
          end
        end

        defp terminate(_count) do
          exit(:normal)
        end

      end

  """

  defmacro __using__(_options) do
    quote location: :keep do

      @behaviour Core

      @doc false
      def init(_parent, _debug, _args) do
        Core.init_ignore()
      end

      defoverridable [init: 3]

    end
  end

end
