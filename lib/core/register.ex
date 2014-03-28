defmodule Core.Register do
  @moduledoc """
  Behaviour for custom process registers.

  `Core` (and `Core.Sys`) can make use of custom registers by using names of the
  form `{ :via, module, name }`. `:gen_server`, `supervisor`, `:gen_event`,
  `gen_fsm`, `:sys` and other modules  from Erlang/OTP can use the custom
  register in the same way. For an example of a custom register see `:global`
  from Erlang/OTP.

  Note: `whereis_name/1` should return `:undefined`, and not `nil`, when there
  is no process associated with a name for compatibility with erlang libraries.
  """

  use Behaviour

  defcallback register_name(any, pid) :: :yes | :no

  defcallback whereis_name(any) :: pid | :undefined

  defcallback unregister_name(any) :: any

end
