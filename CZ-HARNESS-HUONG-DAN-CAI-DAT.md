# CZ-Harness — Hướng dẫn cài đặt & chạy pipeline từng bước

> Tài liệu này hướng dẫn **cài plugin** và **chạy quy trình 11 bước** trên một dự án mới, kèm chỉ rõ file cấu hình nào cần sửa ở đâu. Muốn hiểu kiến trúc/khái niệm trước, xem [CZ-HARNESS-README.md](CZ-HARNESS-README.md).
>
> Ví dụ minh họa trong tài liệu này lấy từ chính project `CalendarApp` — đã được `/cz:init` và đang chạy CZ-Harness thật, nên bạn có thể mở các file được nhắc tới ngay trong thư mục này để đối chiếu.

---

## Mục lục

1. [Yêu cầu trước khi bắt đầu](#1-yêu-cầu-trước-khi-bắt-đầu)
2. [Cài đặt plugin](#2-cài-đặt-plugin)
3. [Khởi tạo dự án — `/cz:init`](#3-khởi-tạo-dự-án--czinit)
4. [File cấu hình cần xem/sửa ngay sau khi init](#4-file-cấu-hình-cần-xemsửa-ngay-sau-khi-init)
5. [Chạy pipeline 11 bước](#5-chạy-pipeline-11-bước)
6. [Vòng lặp build cho từng RD](#6-vòng-lặp-build-cho-từng-rd)
7. [Theo dõi tiến độ real-time](#7-theo-dõi-tiến-độ-real-time)
8. [Chạy tự động (unattended) với `/cz:run`](#8-chạy-tự-động-unattended-với-czrun)
9. [Các lệnh kiểm tra sức khỏe dự án](#9-các-lệnh-kiểm-tra-sức-khỏe-dự-án)
10. [Xử lý sự cố thường gặp](#10-xử-lý-sự-cố-thường-gặp)
11. [Checklist nhanh](#11-checklist-nhanh)

---

## 1. Yêu cầu trước khi bắt đầu

- **Claude Code** đã cài và đăng nhập.
- **Python 3** có sẵn trong PATH (dùng để build audit index và serve usage monitor — `hooks/lib/common.sh` tự dò `python3`/`python`/`py`, kể cả trên Windows).
- **pytest** nếu dự án dùng Python làm test runner mặc định của harness (adapter cho vitest/jest, `go test` cũng có sẵn — đổi qua biến `CZ_TEST_RUNNER`, xem `hooks/lib/test-runner-adapter.sh`).
- Một thư mục project trống hoặc project hiện có — CZ-Harness không đòi hỏi phải bắt đầu từ số 0, chỉ cần chưa có `state/board.json` (dấu hiệu project đã init rồi).

## 2. Cài đặt plugin

CZ-Harness được phân phối qua một **marketplace** (ở đây là marketplace nội bộ `cz-harness-local`, trỏ tới repo GitHub `hungnguyenhypertech-stack/cz-sdlc-plugin`). Cài theo 2 bước: **thêm marketplace**, rồi **cài plugin từ marketplace đó**.

### Bước 2.1 — Thêm marketplace (chỉ cần làm 1 lần trên máy)

Trong Claude Code, gõ lệnh sau (thay đường dẫn/URL bằng nguồn thật bạn được cấp):

```bash
/plugin marketplace add hungnguyenhypertech-stack/cz-sdlc-plugin
```

Hoặc nếu bạn có bản local (ví dụ đang phát triển plugin, hoặc được chia sẻ qua thư mục nội bộ):

```bash
/plugin marketplace add /duong/dan/toi/marketplace
```

### Bước 2.2 — Cài plugin `cz-harness` từ marketplace vừa thêm

```bash
/plugin install cz-harness@cz-harness-local
```

Mở giao diện quản lý plugin bằng `/plugin` nếu muốn thao tác qua menu thay vì gõ lệnh trực tiếp.

### Bước 2.3 — Xác nhận đã cài đúng

Kiểm tra plugin đã bật trong `~/.claude/settings.json` (mục `enabledPlugins`) có dòng:

```json
"cz-harness@cz-harness-local": true
```

Sau đó thử gõ `/cz:` trong Claude Code — danh sách 22 slash command của plugin phải hiện ra trong gợi ý autocomplete. Nếu không thấy, xem [mục 10 — Xử lý sự cố](#10-xử-lý-sự-cố-thường-gặp).

📌 **Lưu ý:** cài plugin chỉ đưa **command/agent/hook/skill/template** vào Claude Code — nó **không** tự tạo bất kỳ file nào trong project của bạn. Bước tạo file thật (`rd/`, `state/`, `config/`...) nằm ở bước tiếp theo.

## 3. Khởi tạo dự án — `/cz:init`

Chạy trong thư mục gốc của project (project có thể trống hoặc đã có code sẵn):

```bash
/cz:init <MA-DU-AN>
```

Ví dụ: `/cz:init CalendarApp` (đúng như project này đã làm).

Lệnh này sẽ **hỏi bạn 2 quyết định quan trọng** trước khi scaffold — cân nhắc kỹ vì đổi sau khi đã có RD sẽ tốn công:

| Quyết định | Lựa chọn | Gợi ý chọn |
|---|---|---|
| **Gate profile** | `light` / `standard` (mặc định) / `heavy` | Bắt đầu với `standard` trừ khi bạn chắc đây là spike/thử nghiệm (`light`) hoặc module cực nhạy cảm ngay từ đầu (`heavy`) |
| **Concurrency mode** | `serial` / `bounded` (mặc định, N do bạn đặt) / `wave` | Mới dùng lần đầu → chọn `serial` hoặc `bounded` với N nhỏ (2–3); `wave` chỉ nên dùng khi đã quen luật phụ thuộc module |

Sau khi xác nhận, `/cz:init` sẽ tạo:

- Thư mục runtime: `rd/`, `tests/`, `evidence/`, `gate-records/`, `telemetry/`, `state/`, `deliverables/` (kèm các thư mục con `adr/`, `reviews/security/`, `coverage/`, `understanding-log/`...)
- File cấu hình: `config/gates.yaml`, `config/hazard-paths.yaml` (copy từ plugin, **bắt buộc** — thiếu file này thì hazard detection bị vô hiệu hóa hoàn toàn mà không có cảnh báo rõ ràng)
- `board/board.html` + `board/build-audit-index.py` (copy từ plugin — thiếu bước này thì `/cz:board` sẽ 404)
- `state/board.json` khởi tạo rỗng, `telemetry/events.jsonl` rỗng
- `deliverables/understanding-log/init.md` — log quyết định đầu tiên (profile/mode đã chọn và lý do)

**Cổng người duyệt:** bước init luôn yêu cầu con người xác nhận profile/mode/`human_gates` mặc định trước khi hoàn tất — không có review AI/security ở bước này.

✅ **Kiểm tra sau init** — các file/thư mục sau phải tồn tại, thiếu 1 trong 2 file đầu là dấu hiệu scaffold lỗi im lặng:
```
config/hazard-paths.yaml
board/board.html
state/board.json
config/gates.yaml
gate-records/index.json
```

## 4. File cấu hình cần xem/sửa ngay sau khi init

Đây là 3 file bạn nên mở ngay sau `/cz:init` để chỉnh cho đúng thực tế dự án — đường dẫn tính từ gốc project (ví dụ trong project này: [config/gates.yaml](config/gates.yaml), [config/delegation-map.yaml](config/delegation-map.yaml), [config/hazard-paths.yaml](config/hazard-paths.yaml)).

### 4.1. `config/gates.yaml` — file quan trọng nhất

| Khối cần chỉnh | Ý nghĩa | Khi nào cần đổi |
|---|---|---|
| `profile:` | light/standard/heavy toàn dự án | Đổi nếu chọn sai lúc init — nên đổi **trước khi** có RD nào tồn tại |
| `module_overrides:` | Nâng/hạ profile theo từng module cụ thể | Điền sau khi có MODULEMAP thật (bước 2 của pipeline) — file mới init để trống có chủ đích, không phải lỗi |
| `smoke_check.command:` | Lệnh "chạy thử cả sản phẩm" (ví dụ `npm test`, `node --test tests/*.test.js`) — mới có từ v1.0.26 | Nên điền sớm nếu dự án có cách chạy tổng thể rõ ràng, để tránh nhiều RD unit-test pass riêng lẻ nhưng ráp lại không chạy |
| `concurrency.mode` / `max_in_flight` | Số RD được chạy song song | Tăng dần khi team quen luật, đừng nhảy thẳng lên `wave` |
| `hazard_paths:` | Glob pattern tự nâng RD lên `heavy` khi diff chạm tới | Phải **khớp 100%** với `config/hazard-paths.yaml` — `/cz:audit` sẽ báo lỗi nếu 2 file lệch nhau |
| `budgets:` | `per_rd_usd_soft` (cảnh báo), `per_wave_usd_hard` (dừng nhận RD mới) | Chỉnh theo ngân sách thật của dự án |
| **`human_gates:`** | Bật/tắt yêu cầu chữ ký người theo từng phase (0–10) | **Đây là khối hay bị sửa nhất** — xem chi tiết bên dưới |

**Về `human_gates` — điểm PM cần hiểu rõ nhất trong toàn bộ file cấu hình:**

- Mặc định: `scope: true` (bước 0, **không thể tắt vĩnh viễn** — luôn được coi là `true` kể cả khi dòng này bị xóa khỏi file), `rd_commit: true` (tách RD luôn cần người commit), **mọi phase còn lại mặc định `false`**.
- `human_gates` **không** kiểm soát việc AI review hay security review có chạy hay không — 2 review đó **luôn chạy** và luôn được ghi vào `gate-records/*.json` bất kể `human_gates` là gì. Nó chỉ kiểm soát bước **duyệt cuối cùng** có cần người bấm "approve" hay tự động thông qua sau khi AI/security pass.
- Sửa file này **không cần gate** — nhưng nên sửa có chủ đích, ghi lại lý do (ví dụ trong `deliverables/understanding-log/`), không sửa "cho tiện" giữa chừng dự án.
- Đổi `human_gates` giữa chừng dự án **chỉ áp dụng cho lần chạy phase tiếp theo** — không mở lại hồi tố một `gate-records/*.json` đã chốt trước đó.

### 4.2. `config/delegation-map.yaml` — chỉnh mức phân quyền

Thường **không cần sửa cấu trúc** (level/leash mặc định theo agent đã hợp lý sẵn) — chỉ cần biết vị trí để tra cứu khi có escalation bất thường, hoặc khi `risk-gov` đề xuất thay đổi và bạn cần review trước khi chấp nhận. Xem giải thích đầy đủ ý nghĩa `Lx`/`leash` trong [README, mục 5](CZ-HARNESS-README.md#5-cấp-độ-lx-và-leash).

### 4.3. `config/hazard-paths.yaml` — danh sách đường dẫn nhạy cảm

Mặc định đã có sẵn các pattern phổ biến (`**/auth/**`, `**/migrations/**`, `**/*secret*`, `**/payment/**`, `**/pii/**`, `.github/workflows/**`...). Thêm pattern đặc thù của dự án bạn vào đây **và** vào `hazard_paths:` trong `gates.yaml` cùng lúc — 2 file lệch nhau sẽ bị `/cz:audit` báo lỗi.

## 5. Chạy pipeline 11 bước

Chạy tuần tự theo đúng thứ tự — mỗi bước từ chối chạy nếu artifact đầu vào của nó chưa tồn tại, nên bạn không thể vô tình nhảy cóc:

```bash
/cz:scope <MA-DU-AN>        # Bước 0 — phạm vi, mục tiêu, phi-mục-tiêu, câu hỏi mở
/cz:spec <MA-DU-AN>         # Bước 1 — yêu cầu đánh số REQ-<code>-nnn
/cz:modulemap <MA-DU-AN>    # Bước 2 — chia REQ vào module, gán layer 0 (nền)/1 (bề mặt)
/cz:arch <MA-DU-AN>         # Bước 3 — thiết kế kỹ thuật, ADR (nền trước, bề mặt sau)
/cz:wbs <MA-DU-AN>          # Bước 4 — Work Breakdown Structure kiểu rolling-wave
/cz:estimate <MA-DU-AN>     # Bước 5 — ước lượng 3 điểm (PERT) mỗi RD, gộp thành tổng
/cz:risk <MA-DU-AN>         # Bước 6 — gán hazard rating + leash mỗi module, đề xuất profile
/cz:rd <wbs-leaf-id>        # Cắt wave hiện tại thành RD claimable (yêu cầu người commit)
```

Sau bước `/cz:rd`, mỗi RD đi qua vòng lặp riêng — xem mục 6.

Cuối cùng, sau khi các RD trong wave đã `accepted`:

```bash
/cz:report <MA-DU-AN>       # Bước 10 — RTM, Weekly, Case-Study, sinh từ dữ liệu thật
```

📌 `/cz:scope` mặc định luôn cần người ký duyệt (không tắt được). Các bước 1–6 mặc định **không** cần chữ ký người (chỉ AI review), trừ khi bạn bật lại trong `human_gates`.

## 6. Vòng lặp build cho từng RD

Đây là phần chạy **theo từng RD**, không phải 1 lần cho cả dự án — có thể chạy song song nhiều RD nếu `concurrency.mode` là `bounded`/`wave`.

```bash
/cz:dor <rd-id>      # Bước 7 — Definition of Ready: RD đã đủ rõ để claim/test/gate độc lập chưa?
/cz:build <rd-id>    # Bước 8 — vòng lặp: test-designer viết test đỏ trước → dev code cho xanh → smoke check (nếu cấu hình) → DEVBOOK
/cz:gate <rd-id>     # Bước 9 — AI review (luôn chạy) → security review (nếu leash A+) → người duyệt (nếu human_gates.gate = true)
```

**Vòng đời trạng thái 1 RD:**

```
draft / blocked_dep
        │  (/cz:dor pass)
        ▼
      ready
        │  (claim)
        ▼
     claimed → red → green → ai_review → (sec_review nếu leash A+) → accepted
```

`/cz:explain <rd-id>` hữu ích ở bất kỳ điểm nào trong vòng lặp này nếu bạn không đọc được log test/gate — nó diễn giải kết quả đỏ/xanh và verdict gate bằng ngôn ngữ thường, không cần biết đọc code.

## 7. Theo dõi tiến độ real-time

```bash
/cz:board            # Mở board/board.html — 4 tab: Workflow, Live board, Deliverables, Audit & Outcomes
/cz:status            # Bản text của board, kèm phát hiện agent đang bị "stall" (đứng yên bất thường)
```

Board tự làm mới ~3 giây, không cần bấm reload. Tab **Audit & Outcomes** là nơi xem estimate vs. actual và rework rate — chỉ số PM thường cần báo cáo nhất.

📌 Nếu vừa có nhiều thay đổi ở `gate-records/` hoặc `telemetry/events.jsonl` mà tab Audit & Outcomes chưa cập nhật, chạy lại thủ công:

```bash
python3 board/build-audit-index.py
```

(File này **không** có hook tự chạy lại — đây là hành vi cố ý, không phải bug.)

## 8. Chạy tự động (unattended) với `/cz:run`

Nếu không muốn gõ tay từng lệnh, dùng orchestrator:

```bash
/cz:run <MA-DU-AN>
```

Lệnh này tự tìm đơn vị việc kế tiếp (1 phase hoặc 1 RD) và chạy đúng command tương ứng, **tự dừng ngay** khi:
- gặp một `human_gates.<phase>` đang bật cần chữ ký người,
- gặp hard-stop (`HS-<code>-nnn>`),
- chạm trần `budgets.per_wave_usd_hard`,
- hoặc hết việc để lên lịch.

Khi dừng, nó báo rõ chính xác lệnh/quyết định nào đang chờ bạn — không tự ý viết gate record hay tự bật `human_gates` để đi tiếp.

## 9. Các lệnh kiểm tra sức khỏe dự án

| Lệnh | Dùng khi nào |
|---|---|
| `/cz:health-check <MA-DU-AN>` | Chấm điểm 7 chiều traceability, **không có gate**, chạy được ở bất kỳ giai đoạn nào — nên chạy định kỳ, không chỉ cuối dự án |
| `/cz:audit <MA-DU-AN>` | Kiểm tra ngược invariant từ git history + telemetry, so `board.json` với 1 lần replay mới — phát hiện lệch dữ liệu |
| `/cz:rebuild-state <MA-DU-AN>` | Tái tạo `state/board.json` thuần từ `telemetry/events.jsonl` — dùng khi nghi ngờ board bị sai lệch |
| `/cz:viva <MA-DU-AN>` | Tập trả lời câu hỏi kiểu governance-review trước buổi họp stakeholder/audit thật |

## 10. Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Gõ `/cz:` không thấy gợi ý command nào | Plugin chưa cài hoặc chưa bật | Kiểm tra `enabledPlugins` trong `~/.claude/settings.json`; chạy lại `/plugin install cz-harness@cz-harness-local` |
| `/cz:init` báo "project đã tồn tại", từ chối chạy | `state/board.json` đã có sẵn | Đây là hành vi bảo vệ có chủ đích — dùng `/cz:status` để xem project hiện tại thay vì init đè lên |
| `/cz:board` mở ra trang trắng / lỗi fetch 404 | `board/` không được copy vào project, hoặc board đang mở từ ngoài cây thư mục project | Kiểm tra `board/board.html` tồn tại trong project; board chỉ chạy đúng khi được serve **từ trong** cây thư mục project |
| Ghi file vào `src/**` bị chặn dù đã claim RD | Chưa có bằng chứng test đỏ (`guard-red-before-green.sh`), hoặc RD chưa đúng trạng thái | Chạy `/cz:build <rd-id>` đúng thứ tự (test-designer viết test đỏ trước); không tự ý ghi thẳng vào `src/**` ngoài luồng |
| Hazard escalation không kích hoạt dù diff chạm path nhạy cảm | Thiếu `config/hazard-paths.yaml` trong project (bug đã sửa từ v1.0.24, nhưng vẫn có thể xảy ra nếu init cũ hoặc copy tay thiếu sót) | Kiểm tra file tồn tại; đối chiếu với `hazard_paths:` trong `gates.yaml` |
| Tab Audit & Outcomes trống dù đã có gate record | `gate-records/index.json` chưa được build lại | Chạy `python3 board/build-audit-index.py` thủ công |
| RD bị "stall" trên board dù đang có agent chạy | Heartbeat quá hạn `stall_threshold_s` (mặc định 180s) trong `gates.yaml` | Kiểm tra agent có thực sự đang treo không bằng `/cz:status`; nếu chỉ là tác vụ dài, cân nhắc tăng `stall_threshold_s` |

## 11. Checklist nhanh

```
[ ] /plugin marketplace add <nguồn>
[ ] /plugin install cz-harness@cz-harness-local
[ ] Xác nhận enabledPlugins trong ~/.claude/settings.json
[ ] /cz:init <MA-DU-AN>  →  chọn profile + concurrency mode
[ ] Kiểm tra config/hazard-paths.yaml và board/board.html đã được tạo
[ ] Mở config/gates.yaml, xem lại khối human_gates cho phù hợp thực tế team
[ ] /cz:scope → /cz:spec → /cz:modulemap → /cz:arch → /cz:wbs → /cz:estimate → /cz:risk
[ ] /cz:rd <wbs-leaf-id>  →  người commit RD split
[ ] Với mỗi RD: /cz:dor → /cz:build → /cz:gate
[ ] /cz:board hoặc /cz:status để theo dõi real-time
[ ] /cz:report khi wave hoàn tất
[ ] /cz:health-check định kỳ để chấm điểm traceability
```

---

Xem lại kiến trúc, vai trò từng agent, và giải thích khái niệm đầy đủ tại [CZ-HARNESS-README.md](CZ-HARNESS-README.md).
