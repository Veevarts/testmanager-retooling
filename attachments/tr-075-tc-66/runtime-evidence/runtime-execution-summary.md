# TR-075 · TC-66 · Runtime execution evidence (2026-06-24)

## Setup

- Cliente: Claude Desktop conectado vía MCP a Salesforce Hosted MCP server
- Package version: VeevartMCPContext POST-merge (con las 4 nuevas classes)
- Tool invoked: `VeevartMCPGuidanceTool.getGuidance` (Apex Invocable Action)
- Inventario de tools disponibles en el persona del MCP server confirmado por Claude:
  - ✅ Get Veevart MCP Guidance (VeevartMCPGuidanceTool) — la nueva del PR
  - ✅ Get Veevart MCP Context (VeevartMCPContextTool)
  - ✅ Run Veevart Focused SOQL (VeevartMCPSOQLTool)
  - ✅ Inspect Existing Salesforce Report Types (VeevartMCPReportTypesTool)
  - ✅ Create or Update Veevart Salesforce Report (VeevartMCPCreateReportTool)
  - ✅ Use Veevart Report Recipes (VeevartMCPReportRecipesTool)
  - ✅ Analyze Large Salesforce Data (VeevartMCPLargeDataTool)
  - ✅ Get Veevart Org Capabilities (VeevartMCPOrgCapabilitiesTool)
  - ✅ Platform sObject reads (Get Object Schema, SOQL Query, Get User Info, etc.)
  - ❌ List Veevart Prompt Templates (VeevartMCPPromptTemplatesTool) — NO expuesta al persona

## Prompt #1 → Scenario 0 + Scenario 6

userRequest: "Explain Veevart context for event terminology"
visibleMcpToolNames: "all"

Result:
- matchedScenario.key = "context-lookup" ✅
- schemaVersion = "veevart.mcp.guidance.v1" ✅
- confidence = "medium" (matchScore 9)
- JSON válido + todos los campos shape esperados presentes
- responseRenderingGuidance contiene las 4 instrucciones esperadas para record links (Scenario 6 PASS)

## Prompt #2 → Scenario 1

userRequest: "Create report for membership renewal risk"
visibleMcpToolNames: "Get Veevart MCP Context"
persona: "read-only"

Result:
- matchedScenario.key = "report-planning-and-creation" (correct match)
- hasMissingRequiredTools: true ✅
- VeevartMCPReportRecipesTool + VeevartMCPReportTypesTool marcados available=false + status="missing_required_tool" ✅
- 2 entries en unsupportedOrMissingToolWarnings ✅
- Instructions de los missing tools NO instruyen a llamar tools ocultas ✅

## Prompt #3 → Scenario 2

userRequest: "Create report for membership renewal risk"
visibleMcpToolNames: "Use Veevart Report Recipes,Inspect Existing Salesforce Report Types,Create or Update Veevart Salesforce Report"

Result:
- matchedScenario.key = "report-planning-and-creation"
- hasMissingRequiredTools: false ✅
- requiresExplicitConfirmation: true ✅ (global)
- VeevartMCPCreateReportTool:
  - available: true
  - writeAction: true
  - status: "requires_confirmation_before_call" ✅
  - requiresExplicitConfirmation: true ✅
- requiredSafetyGates contiene 3 menciones explícitas sobre "explicit confirmation"

## Prompt #4 (intentado) → Scenario 3

Tool requested: `List Veevart Prompt Templates` (VeevartMCPPromptTemplatesTool.listPromptTemplates)
Result: ❌ Tool no encontrada en el MCP server persona.

Claude reportó textual: "List Veevart Prompt Templates ❌ no encontrada"

VERDICT Scenario 3:
- ✅ PASS estructural via:
  - VeevartMCPPromptTemplatesTool.cls inspection confirma legacy fields preservados
    (promptTemplatesJson, templateCount, key, useCase, title, prompt)
  - Apex test `promptTemplatesKeepLegacyFieldsAndExposePlaybookKeys` PASS en CI
  - El código construye templates con tanto fields legacy como nuevos
    (playbookKey, guidanceToolName, guidanceToolClass, guidanceInstructions)
- ⛔ Runtime validation pendiente: el admin del MCP server debe agregar la tool al persona

## Prompt #5 → Scenario 4

userRequest: "Summarize fundraising activity for last quarter"
visibleMcpToolNames: "Get Veevart MCP Guidance,Get Veevart MCP Context,Query Records (SOQL),Get Object Schema (Enhanced)"
persona: "minimal-read"

Result:
- matchedScenario.key = "answer-only-analytics" ✅ (correct intent detection)
- hasMissingRequiredTools: true (VeevartMCPReportRecipesTool no expuesto)
- Steps optional marcados "optional_tool_not_visible" ✅
- Cada step missing tiene fallbackIfMissing con alternativas usando minimal toolset:
  - "Use Get Veevart MCP Context/Search Veevart Context for reporting guidance..."
  - "Use Run Veevart Focused SOQL for targeted SELECT-only validation if visible"
  - "If no query/analytics tool is visible, provide the plan and ask the admin..."
- Guidance no crashea — sigue produciendo plan + clarifying questions + safety gates

## Hallazgo importante (DEFECT)

userRequest del batch previo: "Create **a** report for membership renewal risk"
- Matcheó answer-only-analytics (score 6) en vez de report-planning-and-creation
- Root cause: substring matching naïve en VeevartMCPGuidanceMatcher
  - matchTerm "create report" no se encuentra dentro de "create a report" porque hay "a" en medio
  - matchTerm "renewal risk" matchea +6 en answer-only-analytics y gana
- 3 variantes naturales del lenguaje rompen el matcher:
  - "Create a report..." (con "a")
  - "Build a report..." (con "a")
  - "Create the report..." (con "the")
- Severity: Medium — UX degradation, no correctness violation
  (safety gates siguen protegiendo writes incluso con wrong match)

## Observación adicional (caveat documental)

Cuando el cliente MCP pasa visibleMcpToolNames="all":
- Todos los steps salen available=true, including tools no expuestas en el server
- Es comportamiento by-design (optimización) pero da false positives sobre presencia real
- Sugerido: documentar este caveat en setup docs

