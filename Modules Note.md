
## M1 - AI Foundation

> [!note] Overview
> This is basic/foundation knowledge everyone needs (any role). For a PM, the core concept isn't prompt engineering - it's **context management**. 
> Other more advanced term that help a PM level up the agent's tooling (toward L4) is **human gate** (M6), **agent evaluation** (M7), and **token optimization**.

### Why this module exist

"Understand enough to work" - The whole point: a PM should understands **why AI gets things wrong** (limited context, hallucination) so they can design controls around it, rather then either blindly trusting or blindly distrusting the output.

### Basic concepts 

- **LLM** - Large Language Model. Generate output based on probability.
- **Context/Context Management** - the information fed to the model so it answer within the right scope. *(This is consider most important concept that everything will work around)*
- **MCP** - Model Context Protocol, the standard for a model to connect to tools/data.
- **Tool / Tool use** - the model's ability to call external tools to take action.
- **Agent / Agentic AI** - AI that plan and executes multiple step toward a goal on its own. Like claude, codex, cursor is also called an agent.
- **Multi-Agent/Orchestration** - several agent collaborating on one problem.
- **RAG (Retrieval-Augmented Generation)** - generation grounded by retrieving from a source at query time.
- **Hallucination** - model optimize for a plausible output. It has no built in "I don't know" unless it specifically trained/prompted to say so.
- **HITL - HOTL - HOOTL** - human from approve-each-step → supervise → hands-off.

---

## M2 - AI Toolchain

> [!note] Overview
> The tool is the way an agent do its assigned task. Tools included **built-in tools** (read/write file, web search, etc) or **custom tools/MCP servers**. 
>

> [!important] Key design principle to remember
> **Generic tool + clear description** beat **narrow, task-specific tool**. A narrow tool box the agent into one interpretation of the task; a generic, well described tool let the agent's own reasoning decide how to apply it. T

### Tools for PM: "which job, which tool"

| PM's job                                                  | Suggested tool            | Why                                                        |
| --------------------------------------------------------- | ------------------------- | ---------------------------------------------------------- |
| Draft/cross-check a long requirement                      | Claude / NotebookLM       | Large context window, stay grounded in the source document |
| Research market/competitors with sources                  | Perplexity                | Traceable sources, up to date                              |
| Generate & edit delivery code/scripts                     | Claude Code / Codex       | Agentic, works directly on a repo                          |
| Summarize meetings/internal multi-document material       | NotebookLM / M365 Copilot | Grounded in your own documents                             |
| Quick, general purpose brainstorming                      | ChatGPT / Gemini          | General purpose                                            |
| Excel work, organize mail box, enterprise document seacrh | M365 Enterprise           | Data security, role based access control                   |

### Best practice:
If you try to build a tool, aim for a **generic tool with clear description** instead of a narrow, specific one, an overly specific tool may actually **limit the agent's reasoning power**.

---

## M3 - AI Project Workflow

> [!note] Overview
> The AI workflow (or **AI-SDLC**, a term that's been famous for awhile) is the combination of **agents, skill, tool, rule, memory, verification, gorvernent, telemetry, security**... all of them can be considered the **harness**. There is a very valuable workshop in PMC covering the "harness 7 layers" following **CASAN**.
>
> Building a workflow in a enterprise environment is really about **AI adoption**. A **brownfield** (enhance project), a **greenfield** (build from scratch) project, or an **EOSL/migration** project will have different approach:
> - If we start with **brownfield**, we may need to design first and transformation step by step, like we try to get RD to L3 first, and then CD, and then FUT. **Human in the loop is a must** at the early stage.
> - When we start with **greenfield**, the more cost saving, direct approach is to build the full workflow, and have the time to POC and enhance it by sprints.
> - For **EOSL/migration** project, use AI first to extract and document business rules into a golden master test suite, then support code transformation or platform migration, with human validation against the golden master to ensure legacy parity before decommissioning the old system.

### The whole SDLC, AI-first

At every step, the question is: what does AI do, what does the human do?

```
Requirement -> Planning -> Architecture -> Task Breakdown -> Estimation
-> Coding -> Testing -> Review -> Release -> Retrospective
```

| Phase               | AI does                                                            | Human does                            |
| ------------------- | ------------------------------------------------------------------ | ------------------------------------- |
| Requirement         | Generate a draft, spot contradiction, generate clarifying question | Confirms intent, prioritize, sign off |
| Planning/Estimation | Generate WBS, estimate, flag risk                                  | Adjust to reality, commits            |
| Coding/Testing      | Generate code/test, run, patch                                     | Define "done", review, own quality    |
| Review/Release      | Summarize diff, risk, checklist                                    | Decide on release, audit              |
| Retrospective       | Synthesize telemetry into insight                                  | Decide what to improve                |

### Two operating principle taken from RevenueOS 

**1. Design-first + 4-lens cross-review, *before* letting AI execute.** For anything non trivial, the PM (or architect) write a short design first, then review it through 4 lens: **Requirement, Test/SIT, Acceptance/UAT, Architecture**, locking down the "Definition of Done", **only then** hand it to AI to execute.

Purpose: push disagreement to the cheapest possible moment. Fixing a idea on one page of paper is cheaper then fixing 500 lines AI already generated.

**2. "Foundation first, surface later" (the U-curve).** Build the guardrails first (task assignment rule + telemetry + control gate), then pour on features. Week one pay the "foundation tax" - the thinking cost (architecture, defining Done) + building the base (guardrails, telemetry, gates) + reviewing every file to understand current state. This phase is slow, with little visible output. After that, every feature reuse the guardrails already built, so it ship faster with less bug.

Why a PM need to understand this: so they don't panic when the early pilot phase look "slow but correct," and so they can explain the U shaped productivity curve to leadership.

---

## M4 - Prompting

> [!note] Overview
> Prompting is basic term too, in Q3/Q4 2025 we talk very much about this topic at Fsoft. We also build many long prompt template to resolve task in one shot. But now we translate it into more managable like **skill, rule, schema output**. In other way, you can call **skill is a long prompt**, nothing special.
>
> But with the improvement of AI agent, now you dont need to write prompt/skill by yourself, just give agent a clear goal and let it build for you. The sole responsible remain is only to validation/enhancement.
>
> If you work with Claude workflow, you will see sometime a top agent call a sub agent by a set of prompt they write itself.

### How you build the prompt, and what you ask it to do
**Building the prompt**
- **Structured** - role, context, task, output format. The skeleton to start from.
- **Context Management** - deciding what actually reaches the model. Trimming and ordering the input, not just wording the ask.
- **Few-shot** - showing a worked example or two so the model copies the pattern instead of guessing.

**What you ask it to do**
- **Plan** - have it lay out the steps before executing (e.g Claude plan mode).
- **Review** - have it tear apart its own or someone else's work ("be a tough reviewer"). Where our review gates come from.
- **Execute** - just do the task. 

---

## M5 - AI Delegation

> [!note] Overview
> This module is marked as the most important of the course, because the course aim to build a **AI augument PM**.
>
> This is very specific by project, scenario, but you must understand the **5 levels of CASAN**, match with each current role in the project. Basically, you need to build again the **RACI table** of project, including AI agents.
>
> We not only talk about task delegation, like repeatable task can be converted into skill, we also need to talk about **human transformation** to adapt with AI agent. 
> 
> You can now see some project have a AI champion, or sometime called forward deployment engineer, some AI training course at BU level, FSU level. A good PM not only need to know the way to delegate task, he also need to know the capability of project members.

### The two tools of delegation

**Tool 1 - Delegation Matrix (quick triage).** Two axis: **Risk** x **AI-Doable (AID)**:

|               | AI does it well                | AI does it poorly              |
| ------------- | ------------------------------ | ------------------------------ |
| **Low risk**  | AI do, human spot check        | Human does it, AI assist       |
| **High risk** | AI do + mandatory human review | Human does it, AI don't decide |

**Tool 2 - L0-L5 ladder + the Autonomy Leash.** The Matrix tell you which group a task belong to; the **L0-L5** ladder (FPT CASAN Bible section 6) is the full ruler for how far AI may run on it's own.

| Level | Name | AI may do | Who decide |
|---|---|---|---|
| **L0** | Observe | Observe/summarize, change nothing | - |
| **L1** | Draft | Draft only, human approve 100% | Human |
| **L2** | Recommend | Propose option | Human |
| **L3** | Execute (bounded) | Execute low risk task within a boundary | AI run it, human spot check |
| **L4** | Operate workflow | Operate the whole flow with guardrail + audit + exception handling | AI close the "green" part, human approve exception/hazard |
| **L5** | Restricted/high risk | High autonomy in complex territory | Deliberately not granted, always wait for a human |

Leash **A/A+** are the 2 everyday operating notch cut from L0-L5 (**A is approx L3, A+ is approx L4**). The wider PM population use A/A+ day to day; knowing the underlying L0-L5 ladder is what let you understand where you stand.

> [!warning] Don't confuse 3 similar sounding term 
>
> | Term | What it is | Answer | Relationship |
> |---|---|---|---|
> | **L0-L5 ladder** | The autonomy ruler, 6 notch (FPT standard) | "How far may AI run on it's own?" | The root framework |
> | **Leash A/A+** | 2 practical everyday notch cut from that ladder | "Which notch do I run AI at today?" | A = L3, A+ = L4, same axis as L0-L5, not a new concept |
> | **Harness** | The technical rig wrapped around the model | "What is AI equip with to run?" | A completely different axis, the machine, not the autonomy |
>
> Memory aid (horse pulling a cart): Harness is the tack fitted to the horse (equipment), Leash/L0-L5 is the lead rope deciding how far it may wander (autonomy). PM adjust the rope daily, never touch the tack.

### 3 hard rule (never relaxed)

AI never self push/merge/release (everything stop at a draft awaiting approval). AI never touch secret/key (`.env`, credential, IP). While hard stopped/awaiting approval, AI never self mark Done.

### "Human transformation", the part of this module beyond the tools

Delegation isn't just a task classification exercise, it also require transforming how human on the project adapt to working alongside AI agent. This show up in the wider program as:
- **AI Champions** ("forward deployment engineers") emerging from later cohort.
- BU/FSU level AI training program.
- The course's own "team self mentor" operating model is itself a example of this human transformation principle in action.

A good PM's delegation skill therefore has two half: 
- (1) classify the task correctly
- (2) know the capability of the humans on the project well enough to pair them with AI appropriately, i.e rebuild the project's RACI table with AI agent included as actor.

---

## M6 - AI Governance

> [!note] Overview
> This module explain 3 common mechanism:
> - **Fail-closed gate**
> - **Built-flagged**
> - **Hard-stop on contradiction**
>
> Audit = traceability chain (requirement <-> work item <-> test) + the Dev Book, to find where AI wrong.

### The 3 mechanism in full 

| Mechanism                            | Principle                                                                                                           | How a PM applies it                                                                                                                    |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **Fail-closed gate**                 | AI output only usable when the automatic gate is green. Can't verify equal blocked, never "let it through for now." | Define the minimum gate for any important artifact (must be traceable + have a human reviewer). Missing evidence means not usable yet. |
| **BUILT-flagged, awaiting approval** | AI finish the build but do NOT self release. High risk work stop at "built, gate green, awaiting human approval."   | Separate "AI is done" from "it's released." A human personally approve the hazard part, the safe part AI can self close.               |
| **Hard-stop on contradiction**       | When spec is contradictory/ambiguous, AI must stop and expose it, never guess to keep going.                        | Teach PM to treat "AI stopped and asked" as a good signal, not a bug, the PM adjudicate before unlocking.                              |

### Traceability discipline 

Every important requirement must be traceable requirement <-> work item <-> test. RevenueOS run a automatic "traceability checker" every time a requirement doc change, and loudly report any broken chain.

### The 9 AI transformation anti pattern (FPT CASAN Bible section 20.3)

This table is a self check checklist worth revisiting whenever a project feel "off":

| #   | Anti pattern                                                                        | Module that treat it                                                 |
| --- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| 1   | Buying lots of AI tool while data isn't ready                                       | M2 - M3 (CASAN scoring: data is the foundation layer)                |
| 2   | Using a chatbot to patch the old process instead of redesign the workflow           | M3 (redraw the SDLC AI first, don't glue AI onto old work)           |
| 3   | Putting a agent into a real environment with no delegation architecture             | M5 (L0-L5 ladder + mandatory Delegation Map)                         |
| 4   | Not distinguishing read only vs write capable tools/systems                         | M5 (classify task by impact permission + Leash A/A+)                 |
| 5   | No verification baseline, testing by gut feel                                       | M6 fail closed gate - M7 (measure with data)                         |
| 6   | No AgentOps, blind to cost/quality/error/drift                                      | M7 (dashboard: token, rework, bug, cost, Compression)                |
| 7   | No rollback / emergency stop switch                                                 | M6 (BUILT-flagged awaiting approval - hard stop - approval workflow) |
| 8   | No clear owner for data/model/agent/risk/outcome                                    | M6 Governance (assign owner + audit log + human in the loop)         |
| 9   | Calling everything "AI transformation" but KPI is just license count / prompt count | M7 (measure outcome & real hours, not token/license proxy)           |

---

## M7 - AI Telemetry

> [!note] Overview
> Telemetry is telling everything with real data. Dont primarily only use token count, use real man hour: Traditional work vs working with AI.
>
> 2 most important telemetry is process and volume:
> - **Process:** actual effort, failure/rework count (this not means 0 failure is good but risky).
> - **Volume:** token estimate/actual, AI efficiency (traditional norm/actual effort), token efficiency (**md per 1m token** as unit)

### The 4 honest measurement principle (from RevenueOS's real operating experience)

1. **Measure REAL human hour, NOT a token proxy.** Burning a lot of token don't mean getting a lot done (foundation building phase burn token but produce little visible output). RevenueOS drop converting hour from token count for exactly this honesty problem, it only measure actual hour at the keyboard.
2. **est -> reconcile.** When logged, token count is a estimate, periodically reconcile against actual number and update. Treat a sudden "spike" with caution until reconciled.
3. **Log work *outside* the plan too** (analysis, documentation, meeting), not just shipped task, otherwise the productivity picture get inflated one sided.
4. **Two most "expensive" metric deserve top billing:** Compression = (traditional hour / real hour), show leadership the leverage. **MD/1M-token** = token efficiency, show "eating your own cooking" on M8.

### KPI table

| KPI                                | Formula                                                    | Data source                              | Target (post program)                    |
| ---------------------------------- | ---------------------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| AI Adoption                        | (task using AI / total task) x 100%                        | Task tracker + telemetry log             | at least 60% of PM work                  |
| Planning Lead Time                 | Day to a approvable plan/WBS+estimate                      | PMO record                               | down at least 30%                        |
| Estimation Accuracy                | 1 - \|Actual - Estimate\| / Actual                         | Estimate vs actual at task/project close | up to at least 80%                       |
| AI Productivity                    | Outcome unit / (human hour + AI cost converted)            | Telemetry + timesheet                    | up at least 25%                          |
| Review Time                        | Avg review hour / artifact                                 | Review log                               | down at least 30%                        |
| Rework Rate                        | (artifact redone / total) x 100%                           | QA log                                   | down at least 20%                        |
| Delivery Quality                   | Bug rate (per KLOC or per story) + defect leakage          | QA/Test                                  | should not worsen, aim down              |
| Customer Satisfaction              | CSAT/NPS                                                   | Survey                                   | hold/up                                  |
| Project Margin                     | (Revenue - cost incl token) / Revenue                      | Finance + AI cost                        | up                                       |
| **Compression**                    | (est traditional hour for same volume) / (real human hour) | Effort baseline + logged real hour       | up, the "leverage" number for leadership |
| **Token Efficiency (MD/1M-token)** | (MD delivered) / (million token spent)                     | Telemetry log                            | up, tie directly to M8                   |

### Minimum telemetry to collect (per pilot project)

| Group | Field |
|---|---|
| AI usage | token in/out, which tool, which SDLC phase the task belong to |
| Time | human hour per task, review time, phase lead time |
| Quality | rework count, bug count, defect leakage |
| Economics | token cost (in money), human hour cost (in money), margin |

---

## M8 - AI Economics

> [!note] Overview
> PM should understand AI economy chain: Token -> cost -> velocity -> margin -> ROI. Every token count.

### The value chain (curriculum content, identical framing to my own notes)

```
Token -> Cost -> Velocity -> Margin -> ROI
```

Core message: AI is not free, a PM must optimize AI cost the same way they optimize headcount.

### Why token cost vary (and why a PM should care)

- **Model used** - reasoning depth and cost differ by model family.
- **AI provider** - pricing differ across vendor.
- **License type** - enterprise/controlled data plan vs consumer plan have different cost and data handling term.
