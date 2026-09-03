defmodule PupWatchWeb.PageController do
  use PupWatchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
