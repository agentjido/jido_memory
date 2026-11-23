defmodule Jido.Memory.Directive.Remember do
  @moduledoc "A request to insert or replace one memory record."
  use Jido.Agent.Directive

  @enforce_keys [:collection, :key, :value]
  defstruct [:collection, :key, :value]

  @type t :: %__MODULE__{collection: atom(), key: String.t(), value: map()}
end

defmodule Jido.Memory.Directive.Forget do
  @moduledoc "A request to remove one memory record."
  use Jido.Agent.Directive

  @enforce_keys [:collection, :key]
  defstruct [:collection, :key]

  @type t :: %__MODULE__{collection: atom(), key: String.t()}
end
