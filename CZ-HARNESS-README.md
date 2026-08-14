# CZ-Harness — Tài liệu tổng quan

> **Tên đầy đủ:** CZ-Harness (Customer Zero Harness)
> **Mô tả chính thức:** An AI-native delivery Harness for FPT project managers. RD-driven, fully traceable, real-time observable.
> **Phiên bản:** `1.0.26` (mới nhất tại thời điểm soạn tài liệu này)
> **Tác giả:** HungNQ23
> **Đóng gói dưới dạng:** Claude Code plugin, cài qua marketplace (`cz-harness-local`)
> **Nguồn plugin (marketplace):** GitHub `hungnguyenhypertech-stack/cz-sdlc-plugin`
> **Trạng thái build:** Phase 0–5 (scaffold) theo `CZ-HARNESS-PLAN-v0.4.md` — contract/agent/command/hook/gate/board/docs đã đầy đủ và có test, **chưa có dogfood run hoàn chỉnh** (Phase 7) trên một dự án thật từ đầu đến cuối.

Đây là tài liệu tham khảo kỹ thuật đầy đủ về CZ-Harness. Để biết cách **cài đặt và chạy** plugin, xem file riêng: [CZ-HARNESS-HUONG-DAN-CAI-DAT.md](CZ-HARNESS-HUONG-DAN-CAI-DAT.md).

---

## Mục lục

1. [Vấn đề CZ-Harness giải quyết](#1-vấn-đề-cz-harness-giải-quyết)
2. [6 trụ cột (pillars)](#2-6-trụ-cột-pillars)
3. [Kiến trúc tổng quan](#3-kiến-trúc-tổng-quan)
4. [10 subagent theo vai trò](#4-10-subagent-theo-vai-trò)
5. [Cấp độ `Lx` và `Leash`](#5-cấp-độ-lx-và-leash)
6. [22 slash command](#6-22-slash-command)
7. [9 hook chặn (enforcing hooks)](#7-9-hook-chặn-enforcing-hooks)
8. [3 gate profile](#8-3-gate-profile)
9. [6 skill đóng gói](#9-6-skill-đóng-gói)
10. [Live board & hệ thống Deliverables](#10-live-board--hệ-thống-deliverables)
11. [Quy trình 11 bước & vòng lặp RD](#11-quy-trình-11-bước--vòng-lặp-rd)
12. [File cấu hình dự án](#12-file-cấu-hình-dự-án)
13. [Thay đổi nổi bật gần đây](#13-thay-đổi-nổi-bật-gần-đây)
14. [Giới hạn hiện tại (honest gaps)](#14-giới-hạn-hiện-tại-honest-gaps)
15. [Thuật ngữ nhanh](#15-thuật-ngữ-nhanh)
16. [Tài liệu tham khảo thêm](#16-tài-liệu-tham-khảo-thêm)

---

## 1. Vấn đề CZ-Harness giải quyết

Khi để AI agent tự viết code trong một dự án thật, rủi ro thường không nằm ở chất lượng model mà ở **thiếu kỷ luật quy trình**:

- Không ai bắt buộc viết test trước khi code, nên không rõ "xong" nghĩa là gì.
- Không có state machine nào ngăn một task nhảy thẳng từ "đang làm" sang "đã merge".
- Không có nơi tổng hợp real-time xem nhiều AI agent đang làm gì cùng lúc.
- Không rõ ai đã duyệt một thay đổi, dựa trên căn cứ gì.
- Báo cáo cuối kỳ thường được gom tay từ nhiều nguồn, không sinh ra từ dữ liệu vận hành thật.

CZ-Harness giải quyết các vấn đề này bằng cách **ép buộc ở tầng công cụ (enforced by tooling)**, không dựa vào việc con người tự giác tuân thủ quy trình.

## 2. 6 trụ cột (pillars)

CZ-Harness được xây trên 6 trụ cột năng lực PM cần có khi làm việc với AI agent — mỗi trụ cột có artifact cụ thể, cơ chế ép buộc cụ thể, và chỉ số đo cụ thể:

| Trụ cột | Artifact | Cơ chế ép buộc | Chỉ số đo |
|---|---|---|---|
| **AI Literacy** | `understanding-log/**`, `DEVBOOK-<code>.md` | Mỗi phase command và mỗi RD khi accept đều có 1 câu hỏi "Understanding Gate" bắt buộc người trả lời (không phải AI tự trả lời hộ). Dev Book yêu cầu ≥1 correction do con người thực hiện mỗi RD ở profile `standard` trở lên | Số Understanding Gate đã trả lời ÷ số RD đã accept; số correction ghi nhận mỗi RD |
| **AI Delegation** | `DELEGATION-MAP-<code>.md`, `config/delegation-map.yaml` | Mỗi RD có mức phân quyền (L0–L4) + leash (A/A+) rõ ràng. RD chưa có bản ghi phân quyền thì **không agent nào được claim** — hook kiểm tra map trước khi cho phép chuyển sang `in_progress` | % RD có mức phân quyền rõ ràng; số lượt cấp L4; số sự kiện escalation |
| **Workflow Design** | `rd/*.md`, `state/board.json` | 2 state machine (vòng đời RD, vòng đời gate) được ép ở tầng hook — chuyển trạng thái sai luật bị chặn **trước khi** tới người review | Cycle time theo state; time-in-state; số RD bị stall |
| **Governance & Risk** | `RISK-<code>.md`, `gates.yaml`, `gate-records/*.json` | Gate cố định: AI review → security review → người duyệt, không có đường tắt trừ trường hợp `red_skipped` ở profile Light. Danh sách chặn secret. Không agent nào tự duyệt bài của chính mình | Số lần gate chặn (theo từng bước); số hazard escalation; số hard-stop |
| **Telemetry & Economics** | `telemetry/events.jsonl` | Mọi tool call, mọi lần chạy test, mọi quyết định gate đều sinh 1 event gắn RD id — event thiếu tag bị cách ly, không âm thầm rớt | Chi phí mỗi RD; tỉ lệ nén context; chênh lệch token ước lượng vs. thực tế |
| **Outcome Leadership** | `RTM-<code>.md`, live board, `WEEKLY-<code>.md`, `CASE-STUDY.md` | RTM và báo cáo tuần được **sinh từ registry thật**, không gõ tay. Generator từ chối chạy nếu có orphan link hoặc telemetry chưa đối soát ở profile `standard` trở lên | Tỉ lệ rework; độ chính xác ước lượng mỗi RD; ROI; điểm rủi ro "duyệt cho có" |

### Tín hiệu "duyệt cho có" (rubber-stamp risk)

`rubber_stamp_risk` là chỉ số tổng hợp, mang tính tham khảo, ước lượng khả năng một lượt "duyệt" thực chất chỉ là duyệt cho có, không phải review thật:

```
rubber_stamp_risk = f(
  human_review_minutes_per_1k_ai_output_tokens,   # thấp bất thường = đọc nhanh hơn tốc độ đọc khả dĩ
  corrections_logged_per_RD,                       # gần như bằng 0 qua nhiều RD là một tín hiệu
  gate_pass_on_first_attempt_rate,                 # tỉ lệ pass ngay lần đầu cao bất thường
  seconds_between(artifact_ready, human_approval)  # duyệt gần như tức thì trên artifact không tầm thường
)
```

Đây **không phải công cụ giám sát** — điểm số được tính cho chính người duyệt xem trước tiên, không mặc định dùng để đánh giá hiệu suất. Không yếu tố nào riêng lẻ là bằng chứng có lỗi (một RD tầm thường hợp lý có thể review nhanh và pass ngay lần đầu); tín hiệu chỉ có ý nghĩa khi đọc theo xu hướng qua nhiều RD của cùng một người duyệt.

## 3. Kiến trúc tổng quan

| Lớp | Số lượng | Vai trò |
|---|---|---|
| Subagent | 10 | Thực thi từng bước pipeline theo vai trò, quyền ghi file tối thiểu |
| Slash command | 22 | Giao diện người dùng gọi từng bước/hành động |
| Skill đóng gói | 6 | Tri thức chuyên đề, agent hoặc người dùng tra cứu khi cần lý luận sâu |
| Hook chặn | 9 (+1 cosmetic) | Ép luật ở tầng kỹ thuật — không thể bỏ qua bằng cách "quên" |
| Gate profile | 3 | Mức độ ceremony (light/standard/heavy) |
| Live board | 1 | `board/board.html`, tự làm mới ~3 giây |
| Hệ thống Deliverables | 1 | Mọi tài liệu agent viết ra tự render HTML |

## 4. 10 subagent theo vai trò

| Agent | Model | Bước sở hữu | Cấp độ (L) | Vai trò & trách nhiệm chính | Chỉ được ghi vào | Luật cứng (không được vi phạm dù được yêu cầu) |
|---|---|---|---|---|---|---|
| **`ba`** (Business Analyst) | Opus | Bước 0–1 | L1 | Biến yêu cầu thô thành SCOPE (trong/ngoài phạm vi, câu hỏi mở) và SPEC (yêu cầu kiểm chứng được); soạn RD ứng viên kèm phác thảo acceptance criteria | `deliverables/SCOPE*`, `deliverables/SPEC*`, `rd/*.md` | Gặp mâu thuẫn trong spec → **hard-stop**, ghi thành OPEN QUESTION, không tự chọn phe hay "dung hòa" hộ |
| **`sa`** (Solution Architect) | Opus | Bước 2–3 | L2 | Dịch SPEC/SCOPE thành MODULEMAP (module nào sở hữu trách nhiệm gì) + ARCH + ADR (Architecture Decision Record) cho mọi trade-off không tầm thường | `deliverables/MODULEMAP*`, `ARCH*`, `adr/*.md` | Mọi ADR bắt buộc liệt kê ít nhất 1 phương án đã bị loại + lý do; **không được viết code hay test** |
| **`planner`** (PM analyst/estimator) | Sonnet | Bước 4–5 | L2 | Cắt ARCH/MODULEMAP thành WBS; ước lượng effort/complexity theo RD; ghi estimate ngược vào `rd/*.md` | `deliverables/WBS*`, `EST*`, `rd/*.md` | Mọi estimate bắt buộc nêu rõ giả định (assumptions) — thiếu giả định = output không hợp lệ; không viết code/test |
| **`risk-gov`** (Risk & Governance) | Sonnet | Bước 6 | L2 | Đánh giá rủi ro từng RD (blast radius, khả năng hồi phục, mức nhạy cảm bảo mật); sở hữu delegation map (gán L0–L4 + leash A/A+); đề xuất thay đổi gate profile | `deliverables/RISK*`, `DELEGATION-MAP*`, `delegation-map.yaml`, `rd/*.md` | Chỉ được **đề xuất** thay đổi `gates.yaml`, không bao giờ tự commit — chỉ con người commit |
| **`test-designer`** (QA architect) | Sonnet | Bước 7 & 9 | L3 | Viết test trong `tests/**` bám sát acceptance criteria (mỗi test phải trace về đúng 1 AC); đảm bảo test "đỏ" thật (fail thật trước khi có code); ở bước 9 xác minh lại coverage sau khi dev code xong; đánh giá Definition of Ready (`/cz:dor`) | `tests/**`, `deliverables/coverage/*`, `DOR*`, `understanding-log/rd/*` | Không AC nào được bỏ qua test; không TC nào được tồn tại mà không map về 1 AC cụ thể |
| **`dev`** (Developer) | Sonnet | Bước 8 | L3 | Viết code tối thiểu trong `src/**` để chuyển test đỏ→xanh, theo đúng ARCH/MODULEMAP; gắn comment `RD-<ID>` vào mọi file đụng tới; ghi lại bằng chứng đỏ→xanh; viết DEVBOOK (log đỏ, log xanh, ghi chú refactor) | `src/**`, `deliverables/DEVBOOK*` | Nếu implementation cho thấy ARCH sai/bất khả thi → **dừng lại và báo cáo**, không tự ý lệch thiết kế trong im lặng |
| **`ai-reviewer`** (Validation engineer) | Opus | Gate 1 | **L0** (chỉ có quyền viết báo cáo) | Review độc lập code+test so với AC; bắt buộc chủ động săn 10 loại lỗi cụ thể: test rỗng/tautology, test pass được với stub rỗng, AC thiếu TC, TC lệch AC, drift âm thầm giữa RD và implementation, exception bị nuốt, TODO còn sót, bằng chứng đỏ→xanh giả/thiếu, file thiếu annotation RD, `red_skipped` không có lý do chính đáng | `deliverables/reviews/**`, `understanding-log/rd/*` | **Chỉ đọc, không sửa** — kể cả lỗi nhỏ như gõ sai chính tả; không được tự duyệt gate (`human_approved: true`) dưới bất kỳ hình thức nào; không review lại chính báo cáo cũ của mình mà không đánh giá độc lập lại từ đầu |
| **`sec-reviewer`** (Security reviewer) | Opus | Gate 2 | **L0** | Chỉ chạy khi RD được `risk-gov` gắn leash **A+**; review chuyên sâu bảo mật: injection, bypass auth, rò rỉ secret, deserialization không an toàn, thiếu validate input, leo thang đặc quyền... | `deliverables/reviews/security/**` | Mọi finding critical/high là **chặn cứng**, không được hạ mức nghiêm trọng vì áp lực deadline; không tự duyệt gate; thiếu context để review đủ sâu → phải báo là gap chặn, không được "đoán cho qua" |
| **`agentops`** (AgentOps/telemetry) | Sonnet | Bước 10 (+ cross-cutting `/cz:health-check`) | L3 | Ghi telemetry cho mọi lần chuyển trạng thái RD; duy trì RTM (RD→AC→TC→file→verdict); tổng hợp báo cáo WEEKLY (throughput, RD đang chạy, RD rủi ro, tỉ lệ pass/fail gate) và variance ước lượng vs. thực tế; viết CASE-STUDY cho các RD đáng chú ý; viết HEALTH-CHECK (chấm điểm 7 chiều traceability) | `telemetry/**`, `deliverables/RTM*`, `WEEKLY*`, `CASE-STUDY*`, `HEALTH-CHECK*` | **Append-only tuyệt đối** — không bao giờ sửa/xóa event cũ (muốn sửa thì ghi thêm event mới tham chiếu `correction_of`); không tự ghi `human_approved: true`; không làm mượt số liệu để throughput trông đẹp hơn |
| **`sub-pm`** (Orchestrator) | Sonnet | Điều phối toàn pipeline | **L4** (cao nhất — chỉ là quyền *lên lịch*, không phải quyền *quyết định*) | Đọc `rd/*.md` + `state/` để biết RD nào được claim tiếp, tôn trọng `max_in_flight`; ép luật hazard chạy tuần tự (RD gắn `hazard:true` phải đợi mọi RD khác về 0 mới được chạy); ghi state transition; dispatch agent kế tiếp qua Task tool | `state/**`, `rd/*.md` | Không viết code/test; không có quyền duyệt gate; không sửa `gates.yaml`; không tự chốt việc tách RD (chỉ đề xuất); dispatch = lên lịch, không phải phê duyệt — mọi quyết định gate/approval/split/hard-stop/vượt ngân sách đều đẩy lên cho con người |

📌 **3 điểm hay bị hiểu lầm:**
1. Cấp **L0** (`ai-reviewer`, `sec-reviewer`) là cấp bị trói tay nhiều nhất, không phải cấp thấp/kém quan trọng nhất — quyền lực nguy hiểm nhất trong hệ thống là quyền *duyệt*, nên 2 role đó chỉ được viết báo cáo, không được sửa gì.
2. `sub-pm` ở **L4** (cao nhất được cấp) nhưng **không hề có quyền phê duyệt** — L đo mức độ tự chủ vận hành (được tự dispatch việc), không đo quyền lực quyết định.
3. Không agent nào tự duyệt bài của chính mình — đây là "anti-collusion" invariant, ép bởi hook `guard-role-boundaries.sh` ở tầng kỹ thuật, không phải quy định trên giấy.

## 5. Cấp độ `Lx` và `Leash`

### `Lx` (delegation level) — AI được giao quyền tự hành động tới đâu, thang L0–L5

| Cấp | Ý nghĩa | Agent mặc định |
|---|---|---|
| **L0** | Chỉ đọc / quan sát. Không tạo ra bất kỳ thay đổi nào ngoài báo cáo | `ai-reviewer`, `sec-reviewer` — sống vĩnh viễn ở đây |
| **L1** | Chỉ được soạn nháp; mọi thứ phải qua người review trước khi đi tiếp | `ba` |
| **L2** | Được đề xuất artifact có cấu trúc (kiến trúc, ước lượng, đánh giá rủi ro) để người ký duyệt | `sa`, `planner`, `risk-gov` |
| **L3** | Được thực thi trong phạm vi 1 RD, theo đúng vòng lặp SDD nghiêm ngặt, bị chặn (gate) trước khi merge | `test-designer`, `dev`, `agentops` |
| **L4** | Được điều phối xuyên nhiều RD (lên lịch, chuyển trạng thái) nhưng **không bao giờ** viết code/test hay duyệt gate. Cũng là trần cho hazard work dưới profile `heavy` | `sub-pm` |
| **L5** | **Không bao giờ cấp** — trần chính sách riêng của CZ-Harness (không phải giới hạn từ khung CASAN gốc), nghĩa là "tự chủ hoàn toàn, không người trong vòng lặp" | *(không ai)* |

📌 L càng cao **không** có nghĩa "quyền lực quyết định" càng lớn — nó chỉ đo phạm vi được tự hành động mà không cần hỏi lại.

### `Leash` (mức giám sát) — chỉ có đúng 2 mức, gắn theo từng RD

Đây là **toàn bộ tập giá trị hợp lệ** — schema (`rd.schema.json`, `telemetry-event.schema.json`, `board-state.schema.json`) khai báo cứng `enum: ["A", "A+"]`, không có mức thứ 3. (Một bản sửa lỗi ở v1.0.8 từng gỡ bỏ một thang A/B/C bịa đặt xuất hiện nhầm trong 1 file tài liệu, thay bằng đúng từ vựng A/A+ dùng thống nhất toàn plugin.)

| Leash | Ý nghĩa |
|---|---|
| **A** | Giám sát chuẩn (standard oversight) — chạy đúng trình tự gate, người duyệt ký ở bước cuối. Mặc định cho mọi RD |
| **A+** | Giám sát siết chặt (hazard oversight) — bắt buộc security review, phải có người duyệt được chỉ định rõ tên, duyệt theo từng hành động (per-action approval), bắt buộc có link bằng chứng đính kèm |

**Luật leo thang tự động:** bất kỳ RD nào gắn `hazard: true` thì `dev`/`test-designer` của RD đó tự động bị nâng leash lên A+, bất kể mặc định của agent là gì. Một RD **không có bản ghi delegation (level + leash) thì không agent nào được claim** — hook claim chặn trước khi RD chuyển sang `ready`.

> `Lx` trả lời câu "AI này được tự làm tới đâu trước khi phải hỏi người"; `Leash` trả lời câu "việc này rủi ro tới mức nào nên cần bao nhiêu tầng người kiểm tra". Hai trục độc lập — một agent ở L3 vẫn có thể bị siết leash A+ nếu RD chạm vùng nguy hiểm.

## 6. 22 slash command

11 command map trực tiếp vào 11 bước của pipeline (0–10), 1 command không đánh số nhưng thiết yếu (`/cz:rd`), và 10 command cắt ngang.

| Command | Tham số | Mô tả |
|---|---|---|
| `/cz:init` | `[project-code]` | Scaffold runtime cho dự án mới, chọn gate profile và concurrency mode — **chạy đầu tiên**, không phải 1 trong 11 phase đánh số |
| `/cz:scope` | `[project-code]` | Phase 0 — xác định phạm vi dự án |
| `/cz:spec` | `[project-code]` | Phase 1 — biến scope thành yêu cầu đánh số `REQ-*` |
| `/cz:modulemap` | `[project-code]` | Phase 2 — chia REQ vào module, gán layer foundation/surface |
| `/cz:arch` | `[project-code]` | Phase 3 — thiết kế kiến trúc hệ thống theo modulemap |
| `/cz:wbs` | `[project-code]` | Phase 4 — dựng WBS rolling-wave từ kiến trúc |
| `/cz:estimate` | `[project-code]` | Phase 5 — gộp ước lượng 3 điểm (PERT) theo RD thành tổng dự án |
| `/cz:risk` | `[project-code]` | Phase 6 — đánh giá rủi ro, gán trần phân quyền AI theo module/RD |
| `/cz:rd` | `[wbs-leaf-id]` | Cắt **wave hiện tại** thành RD, đề xuất tách theo 6 luật hợp lệ |
| `/cz:dor` | `[rd-id]` | Phase 7 — đánh giá Definition of Ready cho từng RD (không phải 1 lần cho cả dự án) |
| `/cz:build` | `[rd-id]` | Phase 8 — vòng lặp red-green-refactor cho 1 RD (test-designer rồi tới dev) |
| `/cz:gate` | `[rd-id]` | Phase 9 — gate review thứ tự cố định cho 1 RD (AI, rồi security nếu bị gắn cờ, rồi người nếu `human_gates.gate` = true) |
| `/cz:report` | `[project-code]` | Phase 10 — dựng RTM, tổng hợp telemetry, sinh artifact weekly/case-study |
| `/cz:run` | `[project-code]` | Orchestrator — chạy phase và RD không giám sát, tự dừng khi gặp human gate, hard-stop, vượt ngân sách, hoặc hết việc |
| `/cz:status` | *(không)* | In bảng board dạng text, gồm cả phát hiện agent bị stall |
| `/cz:board` | *(không)* | Mở live board (`board/board.html`) đọc `state/board.json` của dự án hiện tại |
| `/cz:audit` | `[project-code]` | Kiểm tra ngược mọi invariant từ git history và telemetry, so `board.json` với 1 lần replay mới |
| `/cz:explain` | `[rd-id]` | Diễn giải kết quả test đỏ/xanh và verdict gate bằng ngôn ngữ dễ hiểu cho PM không biết code |
| `/cz:health-check` | `[project-code]` | Chấm điểm traceability theo 7 chiều: coverage, change coupling, freshness, orphan rate, review evidence, decision coverage, retrieval quality — **không có gate, chạy được ở bất kỳ giai đoạn nào** |
| `/cz:rebuild-state` | `[project-code]` | Tái tạo lại `state/board.json` thuần từ `telemetry/events.jsonl` |
| `/cz:viva` | `[project-code]` | Tập trả lời câu hỏi kiểu governance-review trước buổi họp stakeholder/audit thật |
| `/usage-monitor` | *(không)* | Mở dashboard Claude Usage Monitor đóng gói sẵn, tự nạp dữ liệu usage thật trên toàn bộ project |

## 7. 9 hook chặn (enforcing hooks)

Đây là **phần "xương sống"** thật sự của plugin — nơi luật được ép ở tầng kỹ thuật, không chỉ nằm trong tài liệu.

| Hook | Vai trò |
|---|---|
| `guard-red-before-green.sh` + `guard-rd-freeze.sh` | Ép **SDD nghiêm ngặt**: không có bằng chứng test đỏ (fail thật) thì không được ghi code khiến test chuyển xanh |
| `guard-state-transition.sh` | Trọng tài **duy nhất** của state machine RD — mọi chuyển trạng thái đi qua đây |
| `guard-role-boundaries.sh` | Chặn hành vi "thông đồng" giữa các vai trò (ví dụ: agent tự duyệt bài của chính mình) |
| `guard-claim-lock.sh` | 1 RD chỉ 1 agent giữ khóa tại một thời điểm, tự nhả khóa theo TTL (lazy reclaim) |
| `detect-hazard.sh` | Tự động nâng mức rủi ro dựa trên **diff thật đang ghi**, không dựa vào module khai báo trên giấy |
| `guard-secrets.sh` | Danh sách chặn (deny-list) các pattern trông giống secret/credential |
| `emit-telemetry.sh` + `project-state.sh` | Pipeline sinh sự kiện đứng sau live board và mọi báo cáo tổng hợp |
| `render-deliverable.sh` *(cosmetic, không chặn)* | Tự render mọi deliverable Markdown thành HTML ngay khi được ghi |

## 8. 3 gate profile

| Profile | Khi dùng | Đặc điểm chính |
|---|---|---|
| **`light`** | Spike, prototype, việc rất nhỏ | Warn-only trên orphan, review overhead tối thiểu, cho phép `red_skipped: true` có điều kiện |
| **`standard`** *(mặc định)* | Đa số dự án thật | Block trên orphan của wave hiện tại; AI review luôn chạy; security review chỉ khi bị hazard/leash A+ kích hoạt |
| **`heavy`** | Module/RD nhạy cảm cao | Block trên orphan; security review **bắt buộc** bất kể hazard/leash; bắt buộc 1 lượt refactor mỗi RD |

Từ v1.0.26, **profile có thể ghi đè ở cấp từng RD** (`rd.profile: light|standard|heavy`) khi RD đạt tiêu chí đơn giản (layer 1, ước lượng ≤1.5h, 1 acceptance criterion) — không còn bị khóa cứng theo module/dự án như trước. Xem chi tiết trong [`config/gates.yaml`](#12-file-cấu-hình-dự-án).

## 9. 6 skill đóng gói

Khác với command (hành động — chạy, sinh file/state mới), **skill là tri thức đóng gói** để agent hoặc người dùng tra cứu và lý luận đúng luật khi cần, không phải đọc lại toàn bộ mã nguồn hook mỗi lần.

| Skill | Dùng khi nào | Nội dung cốt lõi |
|---|---|---|
| **`rd-decomposition`** | Một nhánh WBS cần cắt thành RD; RD hiện tại trông quá to/mơ hồ; hoặc dev/test-designer nghi ngờ 1 RD đang giấu 2 hành vi khác nhau | Bài kiểm tra hợp lệ **6 điểm** cho một RD, và cách đề xuất tách cụ thể nếu không đạt |
| **`sdd-loop`** | Đang build implementation cho 1 RD; cần quyết định 1 lượt ghi vào `src/**` có được phép hay không; giải thích vì sao guard từ chối một lượt ghi | Cơ chế **red-green-refactor nghiêm ngặt** — vòng lặp SDD lõi của toàn plugin |
| **`gate-engine`** | Chạy `/cz:gate`; quyết định RD có cần security review không; giải thích 1 kết quả `gate-records/*.json`; so sánh Light/Standard/Heavy yêu cầu gì ở từng thành phần gate | Cổng review **thứ tự cố định**: AI review → security review (nếu bị gắn cờ) → người duyệt |
| **`traceability`** | Cấp phát/phân tích 1 ID (REQ/RD/AC/TC/WBS/NFR/GATE/HS); quyết định 1 test-case còn "tươi" hay "cũ"; sinh/đọc RTM và các nhóm orphan | Quy ước đặt ID + luật "đóng băng" `content_hash` + 4 loại orphan trong RTM |
| **`devbook`** | Viết `deliverables/DEVBOOK-<rd-id>.md` cuối vòng build; quyết định 1 entry có đạt "sàn correction" theo profile chưa | Chuẩn Dev Book — bằng chứng con người thật sự sửa AI, không phải AI tự chấm mình |
| **`viva-prep`** | Trước buổi `/cz:viva` thật; trước buổi review với stakeholder | Luyện tập buổi hỏi đáp/kiểm toán governance dựa trên chính artifact của dự án |

## 10. Live board & hệ thống Deliverables

- **`board/board.html`** — single-file, tự làm mới ~3 giây, 4 tab: **Workflow, Live board, Deliverables, Audit & Outcomes**. Đọc trực tiếp `../state/board.json`, `../deliverables/index.json`, `../gate-records/index.json` — chỉ chạy đúng khi được serve từ trong cây thư mục dự án (đây là lý do `/cz:init` phải copy `board/` vào project, xem hướng dẫn cài đặt).
- **`board/build-audit-index.py`** — dựng `gate-records/index.json` (audit trail + chỉ số outcome, bao gồm `estimate_variance` mỗi RD). Cần chạy lại thủ công sau khi `gate-records/` hoặc `telemetry/events.jsonl` thay đổi — không có hook tự động chạy lại file này.
- **Deliverables** — mọi tài liệu tường thuật agent viết ra (SCOPE, SPEC, ARCH, RISK, cả 2 lượt gate review, RTM/WEEKLY/CASE-STUDY...) đều mang khối frontmatter YAML nhỏ, và `hooks/render-deliverable.sh` tự render thành HTML sibling (dùng chung 1 stylesheet, không cần author riêng từng deliverable) ngay khi file được ghi, đồng thời giữ `deliverables/index.html` luôn cập nhật thành 1 view lọc được theo agent.

## 11. Quy trình 11 bước & vòng lặp RD

```
0. /cz:scope   → phạm vi dự án
1. /cz:spec    → yêu cầu đánh số REQ-*
2. /cz:modulemap → chia module, layer
3. /cz:arch    → thiết kế kỹ thuật, ADR
4. /cz:wbs     → work breakdown structure
5. /cz:estimate → ước lượng 3 điểm
6. /cz:risk    → gán mức rủi ro + trần phân quyền AI
   /cz:rd      → cắt RD (đơn vị giao việc nhỏ nhất, không đánh số phase)
7. /cz:dor     → Definition of Ready (theo từng RD)
8. /cz:build   → vòng lặp red-green-refactor (test-designer → dev)
9. /cz:gate    → AI review → security review (nếu cần) → người duyệt
10. /cz:report → RTM, Weekly, Case-Study — sinh từ dữ liệu thật
```

**RD (Requirement-Deliverable)** là đơn vị nhỏ nhất, đủ nhỏ để 1 agent claim, test, và gate độc lập — mọi cơ chế khác của plugin xoay quanh khái niệm này. Bước 7–9 chạy **theo từng RD**, không phải 1 lần cho cả dự án — một dự án thật có thể có hàng chục RD chạy `/cz:dor → /cz:build → /cz:gate` song song (dưới concurrency `bounded`/`wave`), mỗi RD được theo dõi độc lập.

**Vòng đời 1 RD:** `draft/blocked_dep → ready (sau /cz:dor pass) → claimed → red → green → ai_review → (sec_review nếu leash A+) → accepted`.

`/cz:run <project-code>` là orchestrator không giám sát — tự hỏi đơn vị việc kế tiếp và chạy đúng command tương ứng, nhưng **tự dừng** ngay khi cần chữ ký người, gặp hard-stop, vượt trần ngân sách theo wave, hoặc hết việc để lên lịch.

## 12. File cấu hình dự án

Toàn bộ hành vi per-project được điều khiển bởi 4 file YAML trong `config/`, do `/cz:init` copy vào project khi scaffold. Đây là các file **quan trọng nhất cần biết vị trí** khi vận hành hoặc điều chỉnh plugin:

| File | Điều khiển gì | Ai được sửa |
|---|---|---|
| **`config/gates.yaml`** | `profile` (light/standard/heavy), `delegation_ceiling`, `module_overrides`, `smoke_check.command`, `concurrency` (mode/max_in_flight/wave_ceiling), `hazard_paths`, `budgets` (soft/hard per RD & per wave), **`human_gates`** (bật/tắt chữ ký người theo từng phase) | Con người sửa trực tiếp; `risk-gov` chỉ được đề xuất |
| **`config/delegation-map.yaml`** | Định nghĩa 6 mức `Lx`, 2 mức `leash`, mặc định level/leash cho từng agent, luật leo thang tự động | `risk-gov` ghi (`deliverables/DELEGATION-MAP*.md` + file này); con người sửa cấu trúc |
| **`config/hazard-paths.yaml`** | Danh sách glob pattern (auth, migrations, secret, payment, pii, CI workflow...) tự động nâng RD chạm vào lên `heavy` bất kể module/profile khai báo | Phải khớp với `hazard_paths` trong `gates.yaml` — `/cz:audit` kiểm tra 2 file này có đồng bộ không |
| **`config/id-scheme.yaml`** | Định dạng ID cho REQ/RD/AC/TC/WBS/NFR/GATE/HS, quy ước hiển thị rút gọn, `project_code` placeholder | Hầu như tĩnh — chỉ đổi khi đổi project code |

📌 **File hay cần sửa nhất khi mới triển khai:** `config/gates.yaml` — đặc biệt khối `human_gates` (mặc định mọi phase đều `true`, chỉ `scope` là không thể tắt) và `concurrency.max_in_flight`. Xem hướng dẫn thao tác cụ thể trong [CZ-HARNESS-HUONG-DAN-CAI-DAT.md](CZ-HARNESS-HUONG-DAN-CAI-DAT.md).

## 13. Thay đổi nổi bật gần đây

**v1.0.26** (mới nhất) — root-cause fix cho vấn đề "thủ tục quá nặng so với việc nhỏ":
1. **Ghi đè profile theo từng RD** — trước đây `light/standard/heavy` chỉ chọn được ở cấp dự án/module.
2. **Giới hạn số lần tách RD** — tối đa 4 RD con, độ sâu 2 cấp (trước đây từng quan sát thấy 1 việc bị tách tới 7 RD con).
3. **Runnability gate (smoke check)** — kiểm tra cả sản phẩm ráp lại có chạy được không, không chỉ từng RD riêng lẻ.
4. **Model routing hợp lý hơn** — `sub-pm` chuyển Opus → Sonnet (không còn quyền phán đoán nào cần Opus).
5. **Gỡ bỏ OmniRoute** — tính năng chưa từng được wire thật, loại bỏ theo yêu cầu người dùng.

Các bản trước đó tập trung vào: sửa lỗi hook silent-fail trên project chưa scaffold (1.0.24), thêm `/cz:health-check` (1.0.22), thêm chế độ xem session-trajectory cho usage monitor (1.0.20), và một loạt audit pass đóng các finding Critical/Major/Minor (1.0.7–1.0.8). Changelog đầy đủ từng phiên bản nằm trong `.claude-plugin/plugin.json` → mục `notes`.

## 14. Giới hạn hiện tại (honest gaps)

Cần nói thẳng những điều này khi giới thiệu plugin cho người khác, tránh PR quá đà:

- **Chưa có dogfood run hoàn chỉnh** (Phase 7 của kế hoạch gốc) — build này chưa từng sản xuất ra 1 "Customer Zero" thật từ đầu đến cuối.
- **Chưa được exercise trên runtime Claude Code thật theo nghĩa tích hợp** — hook mới được kiểm tra cú pháp/schema (unit-level), chưa test tích hợp đầy đủ với việc chặn tool-call thật.
- **Không có nguồn token/cost thật theo từng RD** — `cost_usd` để `null` có chủ đích, vì Claude Code hook chưa có nguồn dữ liệu đáng tin cậy cho việc này.
- **`project_code` vẫn là placeholder** (`PB0X`/`PB04` dùng xuyên suốt template) — cần find/replace toàn dự án khi gán project code thật.
- **OmniRoute đã gỡ bỏ** (v1.0.26) — mọi mention còn lại trong docs cũ được đánh dấu not-applicable, không xóa để giữ lịch sử.

## 15. Thuật ngữ nhanh

| Thuật ngữ | Giải thích ngắn |
|---|---|
| **RD** (Requirement-Deliverable) | Đơn vị công việc nhỏ nhất, có thể claim/test/gate độc lập |
| **ADR** (Architecture Decision Record) | Tài liệu ghi quyết định kiến trúc: phương án đã xét, phương án chọn, hệ quả |
| **Gate** | Cổng kiểm soát bắt buộc: AI review → security review (nếu bị gắn cờ) → người duyệt |
| **Leash A / A+** | Mức độ giám sát — A+ bắt buộc thêm security review, duyệt theo từng hành động |
| **Hazard path** | Đường dẫn nhạy cảm (auth, migration, secret, payment...) tự động nâng mức rủi ro |
| **Profile (light/standard/heavy)** | Mức độ ceremony/thủ tục áp cho dự án, module, hoặc từng RD |
| **Understanding Gate** | Câu hỏi bắt buộc con người tự trả lời khi RD được accept |
| **Rubber-stamp risk** | Tín hiệu ước lượng khả năng một lượt duyệt là "duyệt cho có" |
| **Board** | `board/board.html` — bảng trạng thái real-time của toàn bộ RD/gate |
| **Wave** | Một lô công việc gần hạn được lập kế hoạch chi tiết (rolling-wave planning), phần xa hơn giữ ở mức thô |

## 16. Tài liệu tham khảo thêm

- Bản kế hoạch gốc: `CZ-HARNESS-PLAN-v0.4.md` (2026-07-27)
- Changelog đầy đủ từng phiên bản: `.claude-plugin/plugin.json` → mục `notes`
- Khung 6 trụ cột chi tiết: `docs/PILLAR-MAP.md`
- Hướng dẫn vận hành cho PM không biết code: `docs/OPERATOR-GUIDE.md`
- Chế độ nhẹ (Light profile khi nào hợp lý): `docs/LIGHTWEIGHT-MODE.md`
- Quy ước deliverable/HTML render: `docs/DELIVERABLES.md`
- Quy ước ID & traceability: `docs/TRACEABILITY.md`
- Hướng dẫn cài đặt & chạy pipeline: [CZ-HARNESS-HUONG-DAN-CAI-DAT.md](CZ-HARNESS-HUONG-DAN-CAI-DAT.md)
