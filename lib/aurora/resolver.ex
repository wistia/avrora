defmodule Avrora.Resolver do
  @moduledoc """
  TODO: Make RegistryStorage optional
  """

  alias Avrora.{FileStorage, MemoryStorage, RegistryStorage, Schema}

  @doc """
  Resolves schema by a global ID.

  After schema being resolved it will be stored in memory storage
  with key equal to `global ID`.

  ## Examples

      iex> {:ok, avro} = Avrora.Resolver.resolve(1)
      iex> avro.ex_schema.schema.qualified_names
      ["io.confluent.Paymen"]
  """
  @spec resolve(integer()) :: {:ok, Avrora.Schema.t()} | {:error, term()}
  def resolve(id) when is_integer(id) do
    with {:ok, nil} <- memory_storage().get(id),
         {:ok, avro} <- registry_storage().get(id) do
      memory_storage().put(id, avro)
    end
  end

  @doc """
  Resolves schema be it's name and optionally version. A version could be provided
  by adding `:` and version number to the name (i.e `io.confluent.Payment:5`).

  In case if confluent schema registry url is configured, resolution will take a
  look there first and in case of failure try to read schema from the configured
  schemas folder.

  After schema being resolved it will be stored in memory storage with
  key equal `name` and `name:version`. Also it will be added to the registry if
  it's configured.

  ## Examples

      > {:ok, avro1} = Avrora.Resolver.resolve("io.confluent.Payment")
      > {:ok, avro2} = Avrora.Resolver.resolve("io.confluent.Payment:42")
      > avro1.version
      42
      > avro2.version
      42
      > avro1.ex_schema.schema.qualified_names
      ["io.confluent.Paymen"]
      > avro2.ex_schema.schema.qualified_names
      ["io.confluent.Paymen"]
  """
  @spec resolve(String.t()) :: {:ok, Avrora.Schema.t()} | {:error, term()}
  def resolve(schema_name) when is_binary(schema_name) do
    name = Schema.parse_subject(schema_name)
    version = Schema.parse_version(schema_name)

    with {:ok, nil} <- memory_storage().get(schema_name) do
      case registry_storage().get(schema_name) do
        {:ok, avro} ->
          with {:ok, avro} <- memory_storage().put(name, avro) do
            name = if is_nil(version), do: "#{name}:#{avro.version}", else: name
            memory_storage().put(name, avro)
          end

        {:error, :unconfigured_registry_url} ->
          with {:ok, avro} <- file_storage().get(name), do: memory_storage().put(name, avro)

        {:error, :unknown_subject} ->
          with {:ok, avro} <- file_storage().get(name),
               {:ok, avro} <- registry_storage().put(name, avro.raw_schema),
               {:ok, avro} <- memory_storage().put(name, avro) do
            name = if is_nil(version), do: "#{name}:#{avro.version}", else: name
            memory_storage().put(name, avro)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp file_storage, do: Application.get_env(:avrora, :file_storage, FileStorage)
  defp memory_storage, do: Application.get_env(:avrora, :memory_storage, MemoryStorage)
  defp registry_storage, do: Application.get_env(:avrora, :registry_storage, RegistryStorage)
end
