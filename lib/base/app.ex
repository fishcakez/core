defmodule Base.App do
  @moduledoc false

  use Application.Behaviour

  def start(_type, _args) do
    Base.Debug.Supervisor.start_link()
  end

end
