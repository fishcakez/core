defmodule Core.App do
  @moduledoc false

  use Application.Behaviour

  def start(_type, _args) do
    Core.Debug.Supervisor.start_link()
  end

end
