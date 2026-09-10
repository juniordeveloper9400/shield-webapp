-- ============================================================================
--  0011 · app.agent_request — the agent-registration approval queue
-- ============================================================================
--  An agent recruiting a sub-agent in the app fills the KYC form, verifies the
--  recruit's number over a real OTP, and submits. That submission now lands
--  here as a PENDING request — NOT as an app.agent row. The admin console
--  ("Agent approvals") shows every PENDING request, and an admin either
--    * approves it  — an app.agent row is created at the level / parent / area
--      the admin confirms, and this request is marked APPROVED + linked to it; or
--    * rejects it   — status REJECTED with a reason the recruiter sees.
--
--  So app.agent only ever holds real, approved agents (they show "fully" in the
--  team tree and the portal); a pending recruit shows as a locked
--  "Waiting for approval" card, fed from this table.
--
--  Reuses the app.agent_approval enum (PENDING / APPROVED / REJECTED).
--
--  Idempotent — safe to run more than once:
--    dart run backend/db/apply_migration.dart backend/db/migrations/0011_agent_request.sql --yes
-- ============================================================================

SET search_path TO app, public;

CREATE TABLE IF NOT EXISTS app.agent_request (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              uuid NOT NULL DEFAULT gen_random_uuid(),

    -- Where the recruit should sit, as chosen by the recruiter (the admin may
    -- change level / area on approval).
    parent_agent_id   bigint REFERENCES app.agent(id) ON DELETE SET NULL,
    requested_level   app.agent_level NOT NULL,
    requested_area    text NOT NULL DEFAULT '',
    requested_area_id uuid,

    -- The recruit's identity + KYC, straight from the form.
    name              text NOT NULL,
    phone             text NOT NULL,
    first_name        text NOT NULL DEFAULT '',
    middle_name       text NOT NULL DEFAULT '',
    last_name         text NOT NULL DEFAULT '',
    dob               date,
    aadhaar           text NOT NULL DEFAULT '',
    pan               text NOT NULL DEFAULT '',
    address           text NOT NULL DEFAULT '',
    pincode           text NOT NULL DEFAULT '',
    place             text NOT NULL DEFAULT '',
    account_number    text NOT NULL DEFAULT '',
    photo_path        text,

    -- Workflow.
    status            app.agent_approval NOT NULL DEFAULT 'PENDING',
    reviewer_note     text NOT NULL DEFAULT '',   -- rejection reason, shown in the app
    reviewed_at       timestamptz,
    agent_id          bigint REFERENCES app.agent(id) ON DELETE SET NULL,  -- set on approval

    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_request_status_idx
    ON app.agent_request (status, created_at DESC);
CREATE INDEX IF NOT EXISTS agent_request_phone_idx
    ON app.agent_request (phone);
CREATE INDEX IF NOT EXISTS agent_request_parent_idx
    ON app.agent_request (parent_agent_id);
