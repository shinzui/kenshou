-- | Derive functional and owner conclusions from one frozen evaluation.
module Kenshou.Evidence.Round.Report
  ( module Kenshou.Evidence.Round.Evaluation,
    RoundReport,
    roundReport,
    reportExitCode,
    roundReportValue,
    renderRoundReportText,
    renderRoundReportMarkdown,
  )
where

import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.List (find, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (utctDay)
import Data.Time.Format.ISO8601 (iso8601Show)
import Kenshou.Core.Defect (evaluateScope, scopeApplies, scopeValue)
import Kenshou.Core.Id (RunId, ScenarioId, renderRunId, renderScenarioId)
import Kenshou.Core.Outcome (Outcome (..), renderOutcome)
import Kenshou.Core.Scenario (CohortScope, KnownDefect (..), individualKnownDefects)
import Kenshou.Evidence.Disposition qualified as D
import Kenshou.Evidence.Observation qualified as Run
import Kenshou.Evidence.Owner.Record (OwnerRecord (..), versionClaimRaw)
import Kenshou.Evidence.Round
import Kenshou.Evidence.Round.Evaluation
import Kenshou.Evidence.Round.Plan
import Kenshou.Plan.Catalog (ScenarioInfo (..))
import Kenshou.Plan.Execute (ExecutablePlan (..), ExecutableRun (..))
import Kenshou.Plan.Summary (Attempt (..), PlanSummary (..), SummaryEntry (..))
import System.Exit (ExitCode (..))

data RoundReport = RoundReport
  { definition :: RoundDefinition,
    evaluation :: Evaluation,
    ownerConclusions :: [OwnerTransition],
    baselineObservations :: [Run.Observation],
    newFailures :: [(Run.Observation, Text)],
    missingCoverage :: [Omission],
    plannedRuns :: [RunCoverage],
    infrastructureFailures :: [Run.Observation],
    inconclusiveRuns :: [Run.Observation],
    incompleteEvidence :: [(Run.Observation, Text)],
    incompatibleControls :: [IncompatibleControl],
    scopeOverrides :: [AppliedOverride],
    counts :: [(Text, Int)]
  }

data OwnerTransition = OwnerTransition
  { owner :: Text,
    baseline :: [D.Conclusion],
    candidate :: D.Conclusion
  }

data RunCoverage = RunCoverage
  { ordinal :: Int,
    scenario :: ScenarioId,
    runId :: RunId,
    attempts :: [Attempt],
    observations :: [Run.Observation]
  }

data IncompatibleControl = IncompatibleControl
  { scenario :: ScenarioId,
    catalogRevision :: Maybe Int,
    reason :: Text,
    baseline :: [Run.Observation],
    candidate :: [Run.Observation]
  }

data AppliedOverride = AppliedOverride
  { override :: ScopeOverride,
    declaredScope :: CohortScope,
    conclusions :: [(Text, Text, D.Conclusion)]
  }

roundReport :: RoundDefinition -> RoundInputs -> Evaluation -> Either RoundError RoundReport
roundReport definition inputs evaluation = do
  catalog <- applyScopeOverrides definition.scopeOverrides inputs.catalog
  let baselineObservations = inputs.baselineObservations
      candidates = evaluation.candidate
      candidateHash = snd definition.candidateCohort
      dispositionInput =
        D.DispositionInput
          (Text.pack (iso8601Show evaluation.createdAt))
          inputs.owners
          catalog
          (inputDigest "catalog.json")
          inputs.packageMap
          (inputDigest "package-map.json")
          inputs.coverage
          baselineObservations
      baseline = D.deriveDispositions dispositionInput
      -- Same-hash baseline runs serve as historical evidence only. Feeding them
      -- into the candidate cohort would let an old pass satisfy missing reruns.
      controls = filter ((/= candidateHash) . (.planHash)) baselineObservations
      combined = D.deriveDispositions dispositionInput {D.observations = controls <> candidates}
      candidateIds = Set.fromList (map (.runId) candidates)
      baselineByOwner = groupOn (.owner) baseline
      combinedByOwner = groupOn (.owner) combined
      ownerConclusions =
        [ OwnerTransition owner (map annotate before) (annotate (candidateFor candidateHash candidateIds first rest))
        | (owner, first : rest) <- Map.toAscList combinedByOwner,
          let before = Map.findWithDefault [] owner baselineByOwner
        ]
      candidateConclusions = map (.candidate) ownerConclusions
      newFailures = uncoveredFailures catalog candidates
      plannedRuns = plannedCoverage evaluation
      planOmissions = maybe [] (.coverageDocument.decoded.omissions) evaluation.plan
      missingCoverage =
        planOmissions
          <> [ Omission (Just run.scenario) "planned-run-missing" ("no candidate observation for planned run " <> renderRunId run.runId)
             | run <- plannedRuns,
               null run.observations
             ]
          <> [ Omission (Just scenario) "owner-reproduction-missing" "no compatible candidate observation for required owner coverage"
             | scenario <- Set.toAscList (missingOwnerScenarios candidateConclusions Set.\\ accountedScenarios plannedRuns planOmissions),
               not (any (compatibleWith catalog scenario) candidates)
             ]
      infrastructureFailures = filter ((== InfrastructureFailure) . (.outcome)) candidates
      inconclusiveRuns = filter ((== Inconclusive) . (.outcome)) candidates
      incompleteEvidence =
        [ (run, reason)
        | run <- candidates,
          reason <- case run.labels of
            Run.LabelsUnavailable why -> [why]
            Run.LabelsVerified labels
              | run.outcome == Errored -> ["run-errored"]
              | run.outcome == Failed && null labels -> ["failed-without-label"]
              | otherwise -> []
        ]
      incompatibleControls = incompatibleRuns catalog baselineObservations candidates
      scopeOverrides =
        [ AppliedOverride
            override
            original
            [ (entry.owner, arm, conclusion)
            | entry <- ownerConclusions,
              (arm, conclusion) <- map ("baseline",) entry.baseline <> [("candidate", entry.candidate)],
              usesOverride override conclusion
            ]
        | override <- definition.scopeOverrides,
          original <- Map.findWithDefault [] (override.scenario, override.reference) (declaredScopes inputs.catalog)
        ]
      counts =
        D.summaryCounts candidateConclusions
          <> [ ("newFailures", length newFailures),
               ("missing", Set.size (Set.fromList (mapMaybe (.scenario) missingCoverage))),
               ("infrastructure", length infrastructureFailures),
               ("inconclusive", length inconclusiveRuns),
               ("incomplete", length incompleteEvidence),
               ("incompatibleControls", length incompatibleControls)
             ]
  pure RoundReport {definition, evaluation, ownerConclusions, baselineObservations, newFailures, missingCoverage, plannedRuns, infrastructureFailures, inconclusiveRuns, incompleteEvidence, incompatibleControls, scopeOverrides, counts}
  where
    inputDigest name = Map.findWithDefault "" name definition.inputs
    usesOverride override conclusion =
      any (\run -> run.observation.scenario == override.scenario && affectsClassification override run) conclusion.considered
    affectsClassification override run =
      any ((== override.reference) . fst) run.scope
        || case run.observation.labels of
          Run.LabelsVerified labels
            | run.observation.outcome == Failed ->
                any (`elem` labels) (labelsFor override)
          _ -> False
    labelsFor override =
      [ label
      | info <- inputs.catalog,
        info.id == override.scenario,
        declaration <- maybe [] pure info.knownDefect,
        defect <- individualKnownDefects declaration,
        defect.reference == override.reference,
        label <- defect.expectedFailures
      ]
    annotate conclusion =
      conclusion {D.reasons = conclusion.reasons <> [overrideReason override conclusion | override <- definition.scopeOverrides, usesOverride override conclusion]}
    overrideReason override conclusion =
      D.DispositionReason
        "scope-override"
        [run.observation.runId | run <- conclusion.considered, run.observation.scenario == override.scenario, affectsClassification override run]
        [override.scenario]
        (Just (override.reference <> " " <> override.reason))

groupOn :: (Ord k) => (a -> k) -> [a] -> Map k [a]
groupOn key = Map.fromListWith (flip (<>)) . map (\item -> (key item, [item]))

candidateFor :: Text -> Set.Set Text -> D.Conclusion -> [D.Conclusion] -> D.Conclusion
candidateFor candidateHash candidateIds first rest = fromMaybe fallback (find candidateCohort (first : rest))
  where
    isCandidate run = Set.member run.runId candidateIds
    considered = filter (isCandidate . (.observation)) first.considered
    incompatible = filter isCandidate first.incompatible
    disposition = case (first.cohort, first.disposition) of
      (Nothing, D.Unverifiable) -> D.Unverifiable
      (Nothing, D.NotYetReleased) -> D.NotYetReleased
      _ -> D.NotRun
    reasons =
      [why | first.cohort == Nothing, why <- first.reasons, null why.runs]
        <> [D.DispositionReason "incompatible-revision" (map (.runId) incompatible) (nub (map (.scenario) incompatible)) Nothing | not (null incompatible)]
    fallback = D.Conclusion first.owner first.claim Nothing Nothing disposition reasons (Nothing <$ first.required) considered incompatible
    candidateCohort conclusion = fmap snd conclusion.cohort == Just candidateHash

compatibleWith :: [ScenarioInfo] -> ScenarioId -> Run.Observation -> Bool
compatibleWith catalog scenario run =
  run.scenario == scenario && any (\info -> info.id == scenario && Just info.revision == run.scenarioRevision) catalog

missingOwnerScenarios :: [D.Conclusion] -> Set.Set ScenarioId
missingOwnerScenarios conclusions =
  Set.fromList [scenario | conclusion <- conclusions, (scenario, Nothing) <- Map.toList conclusion.required]

accountedScenarios :: [RunCoverage] -> [Omission] -> Set.Set ScenarioId
accountedScenarios planned omissions = Set.fromList (map (.scenario) planned <> mapMaybe (.scenario) omissions)

uncoveredFailures :: [ScenarioInfo] -> [Run.Observation] -> [(Run.Observation, Text)]
uncoveredFailures catalog candidates =
  [ (run, label)
  | run <- candidates,
    run.outcome == Failed,
    Run.LabelsVerified labels <- [run.labels],
    let excused = applicableLabels run,
    label <- Set.toAscList (Set.fromList labels Set.\\ excused)
  ]
  where
    catalogByScenario = Map.fromList [(info.id, info) | info <- catalog]
    applicableLabels run =
      Set.fromList
        [ label
        | Just info <- [Map.lookup run.scenario catalogByScenario],
          Just info.revision == run.scenarioRevision,
          declaration <- maybe [] pure info.knownDefect,
          defect <- individualKnownDefects declaration,
          scopeApplies (evaluateScope run.packages defect.appliesTo),
          label <- defect.expectedFailures
        ]

plannedCoverage :: Evaluation -> [RunCoverage]
plannedCoverage evaluation = case evaluation.plan of
  Nothing -> []
  Just captured -> map (coverage summaries) plan.runs
    where
      plan = captured.runPlanDocument.decoded
      summaries = [summary | entry <- evaluation.summaries, let summary = entry.document.decoded, summary.planId == plan.planId]
  where
    coverage summaries run =
      let attempts =
            nub
              [ attempt
              | summary <- summaries,
                entry <- summary.entries,
                entry.ordinal == run.ordinal,
                entry.scenario == run.scenario,
                attempt <- entry.attempts
              ]
          ids = Set.fromList (map renderRunId (if null summaries then [run.runId] else map (.runId) attempts))
          observations = filter (\observation -> observation.scenario == run.scenario && Set.member observation.runId ids) evaluation.candidate
       in RunCoverage run.ordinal run.scenario run.runId attempts observations

incompatibleRuns :: [ScenarioInfo] -> [Run.Observation] -> [Run.Observation] -> [IncompatibleControl]
incompatibleRuns catalog baseline candidates =
  [ IncompatibleControl scenario revision reason before after
  | (scenario, runs) <- Map.toAscList (groupOn (.scenario) (baseline <> candidates)),
    let before = Map.findWithDefault [] scenario baselineByScenario
        after = Map.findWithDefault [] scenario candidateByScenario
        revision = Map.lookup scenario revisions,
    reason <-
      ["missing-baseline-control" | null before && not (null after)]
        <> ["incompatible-revision" | revision == Nothing || any ((/= revision) . (.scenarioRevision)) runs]
  ]
  where
    revisions = Map.fromList [(info.id, info.revision) | info <- catalog]
    baselineByScenario = groupOn (.scenario) baseline
    candidateByScenario = groupOn (.scenario) candidates

reportExitCode :: RoundReport -> ExitCode
reportExitCode report
  | not (null report.newFailures) || any (\owner -> owner.candidate.disposition `elem` [D.Regressed, D.StillReproduces]) report.ownerConclusions = ExitFailure 1
  | null report.evaluation.candidate
      || not (null report.missingCoverage && null report.infrastructureFailures && null report.inconclusiveRuns && null report.incompleteEvidence && null report.incompatibleControls)
      || any (\owner -> owner.candidate.disposition `elem` [D.NotRun, D.Unverifiable, D.DifferentFailure]) report.ownerConclusions =
      ExitFailure 3
  | otherwise = ExitSuccess

roundReportValue :: RoundReport -> Value
roundReportValue report =
  object
    [ "schema" .= ("kenshou.round-report/v1" :: Text),
      "roundId" .= report.definition.roundId,
      "mode" .= report.definition.mode,
      "roundDigest" .= report.evaluation.roundDigest,
      "evaluationId" .= report.evaluation.evaluationId,
      "evaluatedAt" .= report.evaluation.createdAt,
      "baseline" .= armValue report.definition.baselineCohort (toJSON (map D.observationValue report.baselineObservations)),
      "candidate" .= armValue report.definition.candidateCohort (toJSON (map D.observationValue report.evaluation.candidate)),
      "owners" .= map ownerValue report.ownerConclusions,
      "newFailures" .= [object ["label" .= label, "observation" .= D.observationValue run] | (run, label) <- report.newFailures],
      "missingCoverage" .= report.missingCoverage,
      "plannedRuns" .= map coverageValue report.plannedRuns,
      "plan" .= fmap planValue report.evaluation.plan,
      "executionSummaries" .= map (.document.artifact) report.evaluation.summaries,
      "infrastructureFailures" .= map D.observationValue report.infrastructureFailures,
      "inconclusiveRuns" .= map D.observationValue report.inconclusiveRuns,
      "incompleteEvidence" .= [object ["reason" .= reason, "observation" .= D.observationValue run] | (run, reason) <- report.incompleteEvidence],
      "incompatibleControls" .= map controlValue report.incompatibleControls,
      "scopeOverrides" .= map overrideValue report.scopeOverrides,
      "separatePerformanceEvidence" .= report.evaluation.comparisons,
      "counts" .= object [Key.fromText name .= count | (name, count) <- report.counts],
      "exitCode" .= case reportExitCode report of ExitSuccess -> 0; ExitFailure code -> code
    ]
  where
    armValue (name, hash) runs = object ["cohort" .= object ["name" .= name, "planHash" .= hash], "observations" .= runs]
    ownerValue entry =
      object
        [ "owner" .= entry.owner,
          "baseline" .= map D.conclusionValue entry.baseline,
          "candidate" .= D.conclusionValue entry.candidate,
          "transition" .= object ["from" .= map (D.renderDisposition . (.disposition)) entry.baseline, "to" .= D.renderDisposition entry.candidate.disposition]
        ]
    coverageValue run =
      object
        [ "ordinal" .= run.ordinal,
          "scenario" .= run.scenario,
          "runId" .= run.runId,
          "attempts" .= run.attempts,
          "observations" .= map D.observationValue run.observations
        ]
    planValue plan =
      object ["name" .= plan.name, "runPlan" .= plan.runPlanDocument.artifact, "coverage" .= plan.coverageDocument.artifact]
    controlValue control =
      object
        [ "scenario" .= control.scenario,
          "catalogRevision" .= control.catalogRevision,
          "reason" .= control.reason,
          "baseline" .= map D.observationValue control.baseline,
          "candidate" .= map D.observationValue control.candidate
        ]
    overrideValue item =
      object
        [ "override" .= item.override,
          "declaredScope" .= scopeValue item.declaredScope,
          "conclusions"
            .= [object ["owner" .= owner, "arm" .= arm, "cohort" .= conclusion.cohort, "disposition" .= D.renderDisposition conclusion.disposition] | (owner, arm, conclusion) <- item.conclusions]
        ]

renderRoundReportText :: RoundReport -> Text
renderRoundReportText = renderReport False

renderRoundReportMarkdown :: RoundReport -> Text
renderRoundReportMarkdown = renderReport True

renderReport :: Bool -> RoundReport -> Text
renderReport markdown report =
  Text.unlines $
    [ heading <> "Round " <> report.definition.roundId <> " (" <> word report.definition.mode <> ")",
      "",
      "Evaluation " <> report.evaluation.evaluationId <> " on " <> showText (utctDay report.evaluation.createdAt),
      "Baseline " <> cohortText report.definition.baselineCohort <> "   " <> showText (length report.definition.baseline) <> " runs",
      "Candidate " <> cohortText report.definition.candidateCohort <> "   " <> showText (length report.evaluation.candidate) <> " runs"
    ]
      <> section "Owners" (concatMap renderOwner report.ownerConclusions)
      <> section "New failures" [runText run <> " label=" <> label | (run, label) <- report.newFailures]
      <> section "Missing coverage" [maybe "" ((<> " ") . renderScenarioId) item.scenario <> item.reason <> "   " <> item.detail | item <- report.missingCoverage]
      <> section "Planned runs" (concatMap renderCoverage report.plannedRuns)
      <> section "Infrastructure failures" (map runText report.infrastructureFailures)
      <> section "Inconclusive runs" (map runText report.inconclusiveRuns)
      <> section "Incomplete evidence" [runText run <> "   " <> reason | (run, reason) <- report.incompleteEvidence]
      <> section "Incompatible controls" (concatMap renderControl report.incompatibleControls)
      <> section "Scope overrides" (concatMap renderOverride report.scopeOverrides)
      <> section "Separate performance evidence" [Text.pack item.path <> "   " <> item.sha256 | item <- report.evaluation.comparisons]
      <> section "Counts" [Text.unwords [name <> "=" <> showText count | (name, count) <- report.counts]]
  where
    heading = if markdown then "# " else ""
    subheading = if markdown then "## " else ""
    section _ [] = []
    section title rows = ["", subheading <> title, ""] <> map ((if markdown then "- " else "  ") <>) rows
    word value = case toJSON value of String text -> text; other -> compact other
    compact = Text.Encoding.decodeUtf8 . LBS.toStrict . encode
    cohortText (name, hash) = name <> " (" <> hash <> ")"
    renderOwner entry =
      let claim = maybe "" (\record -> " status=" <> fromMaybe "(absent)" record.status <> " fixedVersion=" <> fromMaybe "(absent)" (versionClaimRaw record.fixedVersion)) entry.candidate.claim
          transition = Text.intercalate ", " (map (D.renderDisposition . (.disposition)) entry.baseline) <> " → " <> D.renderDisposition entry.candidate.disposition
       in (entry.owner <> claim <> "   " <> transition)
            : concatMap (renderConclusion "baseline") entry.baseline <> renderConclusion "candidate" entry.candidate
    renderConclusion arm conclusion =
      [arm <> "   " <> D.renderDisposition conclusion.disposition <> maybe "" (("   " <>) . cohortText) conclusion.cohort]
        <> [runText run.observation <> "   " <> D.renderResult run.result <> scopeText run.scope | run <- conclusion.considered]
        <> [runText run <> " incompatible-revision" | run <- conclusion.incompatible]
        <> [reason.code <> maybe "" ("   " <>) reason.detail <> " " <> Text.unwords reason.runs | reason <- conclusion.reasons]
    scopeText scopes =
      Text.concat ["   scope " <> reference <> "=" <> if scopeApplies evaluated then "applies" else "outside" | (reference, evaluated) <- scopes]
    renderCoverage run =
      ( renderScenarioId run.scenario
          <> " planned="
          <> renderRunId run.runId
          <> if null run.observations then " missing" else " observed=" <> Text.intercalate ", " (map (.runId) run.observations)
      )
        : [ "attempt "
              <> renderRunId attempt.runId
              <> maybe "" ((" " <>) . renderOutcome) attempt.outcome
              <> maybe "" ((" exit=" <>) . showText) attempt.childExitCode
              <> maybe "" ((" trust=" <>) . Run.renderTrust . (.trust)) (find ((== renderRunId attempt.runId) . (.runId)) run.observations)
          | attempt <- run.attempts
          ]
    renderControl item =
      (renderScenarioId item.scenario <> " " <> item.reason <> " catalog revision=" <> maybe "absent" showText item.catalogRevision)
        : map (("baseline " <>) . runText) item.baseline <> map (("candidate " <>) . runText) item.candidate
    renderOverride item =
      [ renderScenarioId item.override.scenario <> " " <> item.override.reference <> "   " <> item.override.reason,
        compact (scopeValue item.declaredScope) <> " → " <> compact (scopeValue item.override.appliesTo)
      ]
        <> [owner <> " " <> arm <> " " <> D.renderDisposition conclusion.disposition | (owner, arm, conclusion) <- item.conclusions]
    runText run =
      renderScenarioId run.scenario
        <> " run "
        <> run.runId
        <> " "
        <> Run.renderTrust run.trust
        <> " "
        <> renderOutcome run.outcome
        <> " revision="
        <> maybe "unknown" showText run.scenarioRevision
        <> maybe "" ((" exit=" <>) . showText) (Map.lookup run.runId childExits)
    childExits =
      Map.fromList
        [ (renderRunId attempt.runId, code)
        | summary <- report.evaluation.summaries,
          entry <- summary.document.decoded.entries,
          attempt <- entry.attempts,
          Just code <- [attempt.childExitCode]
        ]

showText :: (Show a) => a -> Text
showText = Text.pack . show
