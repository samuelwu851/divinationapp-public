"""案例库的表结构。

MIGRATIONS[i] 是"从版本 i 升到版本 i+1"要执行的 SQL。
已经发布过的条目永远不改，只在末尾追加新版本。
"""

SCHEMA_V1 = """
-- 案主：一个案主名下可以有多份笔记
CREATE TABLE subjects (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    remark     TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at TEXT                                  -- 预留给回收站，暂不使用
);

-- 笔记：正文 body 是编辑器(TipTap)的 JSON 文档，图片和排盘是其中的节点；
-- body_text 是后端从 body 里抽出的纯文字，给列表预览和搜索用（由后端维护，前端不用管）
CREATE TABLE notes (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    title      TEXT NOT NULL DEFAULT '',
    body       TEXT NOT NULL DEFAULT '',
    body_text  TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    deleted_at TEXT                                  -- 预留给回收站，暂不使用
);


-- notes 和 subjects 的对应关系，一个note可以有多个案主，一个案主也可以有多个notes
CREATE TABLE notes_subjects(
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    PRIMARY KEY (subject_id, note_id)
) WITHOUT ROWID;
CREATE INDEX idx_note_subjects_note ON notes_subjects(note_id);



-- 笔记手动标注的术数（用于没有排盘的随笔）
-- 笔记最终涉及的术数 = 这里手动标的 ∪ charts 里排盘的 type
CREATE TABLE note_types (
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    type    TEXT NOT NULL,                           -- 取值同 charts.type
    PRIMARY KEY (type, note_id)
) WITHOUT ROWID;
CREATE INDEX idx_note_types_note ON note_types(note_id);

-- 排盘：每份笔记里的盘独立一份，存入后不再修改
CREATE TABLE charts (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id       INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    type          TEXT NOT NULL,                     -- bazi / iching / liuren ...
    title         TEXT NOT NULL DEFAULT '',          -- 可不填，如卦的所问之事
    params_json   TEXT NOT NULL,                     -- 排盘请求原样
    snapshot_json TEXT NOT NULL,                     -- 排盘结果原样
    algo_version  TEXT NOT NULL,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_charts_note ON charts(note_id);

-- 排盘的可检索特征：由各术数的拆特征函数生成，可随时重建
CREATE TABLE chart_facts (
    chart_id INTEGER NOT NULL REFERENCES charts(id) ON DELETE CASCADE,
    type     TEXT NOT NULL,
    key      TEXT NOT NULL,
    value    TEXT NOT NULL,
    PRIMARY KEY (type, key, value, chart_id)
) WITHOUT ROWID;
CREATE INDEX idx_facts_chart ON chart_facts(chart_id);

-- 图片记录：文件本身存在磁盘上，这里只记文件名
CREATE TABLE attachments (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id       INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    filename      TEXT NOT NULL UNIQUE,              -- 程序生成的唯一文件名
    original_name TEXT NOT NULL DEFAULT '',          -- 用户原文件名，仅供显示
    width         INTEGER,
    height        INTEGER,
    byte_size     INTEGER,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_attachments_note ON attachments(note_id);

-- 标签：笔记和排盘共用同一份清单(用于记录这个笔记或者排盘是用来干什么的，比如疾病、感情之类)
CREATE TABLE labels (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE note_labels (
    note_id  INTEGER NOT NULL REFERENCES notes(id)  ON DELETE CASCADE,
    label_id INTEGER NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (label_id, note_id)
) WITHOUT ROWID;
CREATE INDEX idx_note_labels_note ON note_labels(note_id);

CREATE TABLE chart_labels (
    chart_id INTEGER NOT NULL REFERENCES charts(id) ON DELETE CASCADE,
    label_id INTEGER NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (label_id, chart_id)
) WITHOUT ROWID;
CREATE INDEX idx_chart_labels_chart ON chart_labels(chart_id);

-- 特点：只贴在排盘上，手动记录这个盘有什么特别之处（如从格、伤官见官）
CREATE TABLE tags (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE chart_tags (
    chart_id INTEGER NOT NULL REFERENCES charts(id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES tags(id)   ON DELETE CASCADE,
    PRIMARY KEY (tag_id, chart_id)
) WITHOUT ROWID;
CREATE INDEX idx_chart_tags_chart ON chart_tags(chart_id);


"""




# V2：标签按「添加的先后」排序。
# note_labels / chart_labels 是 WITHOUT ROWID 表，没有隐含的插入顺序，所以加一列 seq：
# 每份笔记（每个排盘）里从 1 开始递增，新加的标签 seq 最大，排在最后。
# 注意 SQLite 的 ALTER TABLE ADD COLUMN 只能用常量默认值（不能用 datetime('now')），
# 所以用整数序号而不是时间；旧数据 seq 都是 0，再按名字排。
SCHEMA_V2 = """
ALTER TABLE note_labels  ADD COLUMN seq INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chart_labels ADD COLUMN seq INTEGER NOT NULL DEFAULT 0;
"""


MIGRATIONS = [SCHEMA_V1, SCHEMA_V2]
