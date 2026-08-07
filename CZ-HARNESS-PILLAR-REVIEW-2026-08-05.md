# CZ-Harness — Đánh giá theo 6 Pillar Năng lực PM AI-Native

**Đối tượng đánh giá:** plugin `cz-harness`, phiên bản `1.0.11-phase0` (`.claude-plugin/plugin.json`)
**Ngày đánh giá:** 2026-08-05
**Phạm vi:** đọc trực tiếp mã nguồn, hook, schema, config, tài liệu vận hành của plugin (`Plugin/Output/cz-harness/`), đối chiếu với dữ liệu vận hành thật của project AI-bootcamp (41 RD theo dõi, 58 gate-records, `deliverables/understanding-log/**`) — không chỉ dựa vào mô tả trong tài liệu.
**Khung đánh giá:** 6 pillar năng lực PM AI-native, thang điểm 0–4. Tốt nghiệp yêu cầu điểm trung bình ≥ 2.5 và không pillar nào bằng 0.

Ghi chú quan trọng: chính plugin có một tài liệu nội bộ tên `docs/PILLAR-MAP.md` tự map vào đúng 6 pillar này (cùng tên gọi), kèm cơ chế enforce và metric cho từng pillar. Mọi cơ chế được nêu trong tài liệu đó đã được kiểm chứng lại bằng cách đọc hook/code thực tế và dữ liệu project thật, không lấy nguyên si lời tự nhận của tài liệu.

---

## Bảng điểm tổng hợp

| Pillar | Điểm (0–4) |
|---|---|
| C1 — AI Literacy | **4** |
| C2 — AI Delegation | **4** |
| C3 — Workflow Design | **3** |
| C4 — Governance & Risk | **4** |
| C5 — Telemetry & Economics | **3** |
| C6 — Outcome Leadership | **3** |

**Điểm trung bình: 3.5/4** — vượt ngưỡng tốt nghiệp (≥2.5), không pillar nào bằng 0.

---

## C1 — AI Literacy: 4/4

**Cơ chế:** mọi lệnh phase (`commands/cz-*.md`) và mọi RD khi đóng gate đều bắt buộc một câu hỏi **Understanding Gate** — câu hỏi kiểm tra hiểu bản chất, không phải checkbox — và câu trả lời phải do con người viết khi `human_gates.<phase>` bật.

**Bằng chứng thật** (không phải mô tả trong tài liệu): `deliverables/understanding-log/rd/RD-AIBOOTCAMP-013.02.md` ghi lại câu hỏi *"Explain in plain terms what RD-AIBOOTCAMP-013.02 now lets a user do, and one way it could still fail"* — câu trả lời nêu đúng 2 failure mode bậc hai (mảng `tags` bị chia sẻ theo tham chiếu ra ngoài store; `localStorage` vượt quota gây lệch state giữa UI và dữ liệu đã lưu). Đây là hiểu đúng giới hạn hệ thống, không phải trả lời cho có.

**Bằng chứng ở tầng thiết kế:** `config/model-routing.yaml` chủ động lệch khỏi pattern chuẩn của CASAN (escalate model chỉ sau khi validation fail) và giải thích rõ lý do — *"a cheap reviewer that misses a fake test costs more than it saves."* Đây là hiểu đúng năng lực/giới hạn model để ra quyết định có chủ đích, không học vẹt khung lý thuyết.

**Điểm trừ nhỏ, không đáng kể:** cơ chế phát hiện hallucination/drift được `docs/CASAN-MAPPING.md` công khai gắn nhãn "DEFERRED" — bản thân việc công khai giới hạn này (thay vì giả vờ đã có) chính là bằng chứng literacy, không phải điểm yếu.

---

## C2 — AI Delegation: 4/4

**Cơ chế:** `config/delegation-map.yaml` là bộ phân loại AI-do / Human-do / AI-review / Human-review / AI-should-not-do **vận hành thật** ở tầng hook, không phải sơ đồ minh họa:

- L0 (`ai-reviewer`, `sec-reviewer`) = chỉ đọc/review, không bao giờ ghi.
- L1 (`ba`) = draft, 100% người review trước khi đi tiếp.
- L3 (`test-designer`, `dev`) = thực thi trong phạm vi RD, luôn qua gate trước khi merge.
- L4 (`sub-pm`) = điều phối liên-RD, không bao giờ ghi code/test hay tự duyệt gate.
- L5 = **không bao giờ cấp**, là giới hạn cứng do chính CZ-Harness đặt ra (không phải giới hạn của CASAN).

RD không có bản ghi delegation thì không agent nào claim được — kiểm tra ở hook trước khi cho phép chuyển trạng thái, không phải bắt lỗi ở bước review sau.

**Bằng chứng mạnh nhất:** hệ thống tự bắt được lỗi phân loại sai của chính nó. `rd/RD-AIBOOTCAMP-015.03` đến `015.07` có log thật ngày 2026-08-03:

> *"Metadata correction (orchestrator): reclassified hazard: false/leash: A → hazard: true/leash: A+ ... the original /cz:rd cut under-classified this."*

Đây là delegation matrix bắt được một ca đánh giá thiếu rủi ro thật trong vận hành và tự sửa, có ghi log minh bạch — không phải lý thuyết suông.

---

## C3 — Workflow Design: 3/4

**Cơ chế:** 11 lệnh phase (`cz-scope` → `cz-report`) map đúng chuỗi SDLC (Requirement → Planning → Architecture → ... → Retrospective), mỗi phase có cờ `human_gates.<phase>` riêng trong `config/gates.yaml`, cộng vòng DoR → Build → Gate cho từng RD. Thứ tự các bước được ép bằng hook (`hooks/guard-pipeline-order.sh`), không chỉ dựa vào con người tự giác làm đúng thứ tự.

**Điểm trừ:** không có cấu trúc "4-lens cross-review" (Requirement / Test-SIT / Acceptance-UAT / Architecture) như một khối riêng biệt. Các tầng review của plugin được tổ chức theo **danh tính reviewer** (AI review → security review → human approval), không theo 4 lens nội dung. Là một workflow thật và được ép buộc chặt, nhưng khác hình dạng so với mô hình 4-lens.

---

## C4 — Governance & Risk: 4/4

**Cơ chế:** gate fail-closed (AI review → security review → human approval, không có đường tắt trừ ngoại lệ `red_skipped` đã ghi log ở Light profile), hard-stop khi phát hiện mâu thuẫn (`HS-<proj>-<nnn>`, trạng thái `blocked_hardstop`), deny-list secrets chặn ngay khi ghi (không phải bắt ở review sau), hazard-path tự động escalate bất kể module tự khai là gì, không tự merge (agent tạo ra thay đổi không thể là danh tính duyệt thay đổi đó).

**Bằng chứng governance chủ động, không chỉ phản ứng:** `docs/SECURITY-NOTES.md` cảnh báo trước hai rủi ro doanh nghiệp cụ thể — TLS fingerprint stealth (JA3/JA4) và MITM decryption của adapter OmniRoute *"sẽ fail security review của FPT ngay khi nhìn thấy"* — cùng cảnh báo không được dùng provider bị gắn cờ ToS. Đây là rủi ro được vạch ra trước khi ai đó vấp phải, không phải xử lý sau sự cố.

**Bằng chứng governance-in-action thật:** ca tự sửa phân loại rủi ro RD-AIBOOTCAMP-015.03–015.07 nêu ở C2 chính là governance vận hành thật, có audit trail rõ ràng.

**Điểm trừ nhỏ:** không có khái niệm "IP" (bản quyền/license bên thứ ba) tách biệt khỏi secrets — phạm vi rò rỉ IP qua code do AI sinh ra là rủi ro khác với rò rỉ credential, và hiện chưa được đặt tên riêng trong hệ thống.

---

## C5 — Telemetry & Economics: 3/4

**Cơ chế:** schema telemetry (`schemas/telemetry-event.schema.json`) theo dõi token in/out, `cost_usd`, `cost_source` (gateway/estimated/subscription), `tier`/`model`, `human_minutes`; `config/gates.yaml` có ngân sách mềm/cứng theo RD và theo wave; board có tab Audit & Outcomes với cột Estimate/Actual (`estimate_variance`).

**Bằng chứng economics-literacy đáng chú ý:** `docs/SECURITY-NOTES.md` mục "Cost Accounting Caveat" tự cảnh báo rằng provider dạng subscription báo cáo **$0** trong analytics, khiến *"a project... will look artificially cheap — 'artificially' in a direction that flatters the project's own ROI story."* Đây là một cái bẫy kinh tế học thật, được vạch ra chủ động trước khi ai đó dùng con số đó để tự lừa dối chính mình về ROI.

**Điểm trừ:**
1. ROI/margin chưa bao giờ thực sự được tính — đây là lựa chọn có chủ đích (không bịa số khi chưa có nguồn dữ liệu doanh thu thật), nhưng vẫn là một mắt xích còn thiếu trong chuỗi Token → Cost → Velocity → Margin → ROI.
2. KPI "Token Efficiency" dùng đơn vị RD-count/1k-token, không tính theo man-day/1M-token — hai cách đo không so sánh trực tiếp được nếu cần đối chiếu với công thức chuẩn của khung năng lực.

---

## C6 — Outcome Leadership: 3/4

**Cơ chế:** `rubber_stamp_risk` — tín hiệu đo khả năng một lượt "approve" của con người là rubber-stamp chứ không phải review thật, tính từ tốc độ đọc, số correction, tỷ lệ pass ngay lần đầu, và thời gian giữa lúc artifact sẵn sàng với lúc được duyệt. Điểm đáng chú ý là cách tài liệu định vị cơ chế này: *"is not surveillance... surfaced to the participant's own awareness first... a mirror, not a leash."* Đây là tư duy quản lý người trưởng thành — dùng dữ liệu để mở hội thoại, không phải để trừng phạt.

**Bằng chứng dịch thuật quản trị thật:** `deliverables/DELEGATION-MAP-AIBOOTCAMP.md` (tài liệu thật của project) — `risk-gov` tự tạo thêm thang leash tường thuật A/B/C để `sub-pm` "lên lịch thông minh hơn," nhưng nói rõ ràng giới hạn của chính mình: *"config/delegation-map.yaml formally recognises only two leash values... I am not escalating myself or any other agent's level."* Đây là năng lực dịch cơ chế kỹ thuật thành ngôn ngữ điều hành cho người ra quyết định, mà không tự ý vượt quyền hạn được cấp — đúng tinh thần "dẫn dắt team Human+AI hướng tới outcome mà không lạc trong công cụ."

**Điểm trừ:** margin/ROI — outcome mà pillar này gọi đích danh — vẫn là mắt xích yếu nhất toàn hệ thống (xem C5). Ngoài ra, năng lực lãnh đạo con người thật sự (điều phối xung đột, tạo động lực, ra quyết định nhân sự) chỉ có thể suy luận gián tiếp từ một artifact phần mềm, không thể quan sát trực tiếp qua code/hook/config.

---

## Kết luận

Điểm trung bình 3.5/4, vượt ngưỡng tốt nghiệp, không pillar nào ở mức 0. Điểm mạnh nhất và nhất quán nhất là các cơ chế đã **tự bắt lỗi của chính mình trong vận hành thật** (ca phân loại rủi ro RD-015.03–015.07) và **chủ động cảnh báo rủi ro trước khi xảy ra** (SECURITY-NOTES.md). Khoảng trống lớn nhất và xuyên suốt hai pillar C5/C6 là vòng lặp margin/ROI — chưa bao giờ thực sự chảy vào hệ thống đo lường, đúng vì hệ thống từ chối bịa số khi chưa có nguồn dữ liệu thật, nhưng đây vẫn là phần cần bổ sung nếu muốn đo "outcome" theo đúng nghĩa mà C6 đặt ra.
