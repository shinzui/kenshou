-- | Named resources a scenario requires besides PostgreSQL, and the providers that
-- suites register for them. A scenario names its resources in
-- 'Kenshou.Core.Env.EnvRequirements'; a bundle contributes one 'ResourceProvider'
-- per name; the kernel normalizes the specification value, provisions the resource
-- around a local run, hands each worker the provisioned value, and records a
-- fingerprint in the run result.
module Kenshou.Core.Resource
  ( ResourceName,
    mkResourceName,
    renderResourceName,
    ProvisionedResource (..),
    CellBinding (..),
    ResourceProvider (..),
  )
where

import Data.Aeson (Value)
import Data.Text (Text)
import Kenshou.Core.Context (RunContext)
import Kenshou.Core.Resource.Types

data ResourceProvider = ResourceProvider
  { name :: ResourceName,
    summary :: Text,
    -- | Turn the run specification's value, absent when the specification omits
    -- the resource, into the complete validated value the provider acts on. This
    -- is where defaults apply and bad input is rejected; the effective run
    -- specification records the result, so the comparison key hashes it.
    normalize :: Maybe Value -> Either Text Value,
    -- | Acquire the resource for one local run and release it when the action
    -- returns or throws. The run directory in the context is where a provider keeps
    -- its logs.
    withLocal :: forall a. RunContext -> Value -> (ProvisionedResource -> IO a) -> IO a,
    -- | How the resource is bound on a leased cell; 'Nothing' rejects cell placement
    -- for scenarios that require it.
    cell :: Maybe CellBinding
  }
