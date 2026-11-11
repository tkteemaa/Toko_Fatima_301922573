# Cloud Architecture for SplashPoint Swim School — Nigeria-Resident, NDPA-2023-Compliant

**Portfolio 5 — Distributed and Cloud Database Exercise**

This note describes the production cloud architecture for SplashPoint Swim School, keeping **all personal data of SplashPoint swimmers inside Nigeria** by design (the **Nigeria Data Protection Act 2023 (NDPA 2023)** allows cross-border transfers only under ss. 41–43, so keeping data at home avoids that burden), with extra protection for **children's personal data**, and explicit **CAP theorem** placement and **sync vs async replication** trade-offs.

---

## 1. Regulatory context — NDPA 2023

The Nigeria Data Protection Act 2023 (signed into law on 12 June 2023) establishes the Nigeria Data Protection Commission (NDPC) and imposes obligations on data controllers and processors operating in Nigeria. Key provisions relevant to SplashPoint:

| Provision | What it means for SplashPoint |
| --- | --- |
| **Lawful basis & consent** (ss. 25–26) | Swimmers (or guardians for under-18s) must consent to collection and processing of their personal data. |
| **Cross-border transfer** (ss. 41–43) | Personal data may only be transferred outside Nigeria if the recipient country has adequate protection, or the data subject has consented, or one of the lawful conditions applies. For SplashPoint we keep data **resident in Nigeria** by default — no cross-border transfer needed. |
| **Children's data** (s. 31) | Processing of a child's personal data requires **parental consent**; data must be **minimised**; children's data must not be used for targeted advertising or profiling that could harm them. |
| **Purpose limitation & storage limitation** (s. 24) | Personal data must be deleted when the purpose for which it was collected is no longer relevant. SplashPoint sets retention limits (see §5 below). |
| **Security obligations** (s. 39) | Data controllers must implement appropriate technical and organisational measures: encryption, access control, audit logging. |
| **Breach notification** (s. 40) | Breaches likely to risk individuals' rights must be reported to the NDPC within 72 hours; affected data subjects are told immediately where the risk is high. |
| **Data Subject Rights** (ss. 34–38) | Swimmers can request access, rectification, erasure, data portability. SplashPoint must support these. |

References:
- Federal Republic of Nigeria (2023) *Nigeria Data Protection Act, 2023* (Act No. 37). Nigeria Data Protection Commission (ndpc.gov.ng).
- NDPC (2025) *NDP Act General Application and Implementation Directive (GAID) 2025*.

---

## 2. Architecture diagram

```
                              ┌─────────────────────────────────────────────┐
                              │      SplashPoint Cloud (Nigeria region)     │
                              │                                             │
   ┌────────────┐             │   ┌─────────────────────────────────────┐  │
   │  Web app   │──── HTTPS ─►│   │   Application tier (Lagos AZ-A)     │  │
   │ (frontend) │             │   │   Next.js on a managed k8s cluster  │  │
   └────────────┘             │   └────────────┬────────────────────────┘  │
                              │                │                            │
                              │   ┌────────────▼────────────────┐           │
                              │   │  PostgreSQL primary (CP)    │           │
                              │   │  Lagos AZ-A  •  port 5432   │           │
                              │   │  pool, lane, instructor,    │           │
                              │   │  swimmer, lesson_session,   │           │
                              │   │  enrolment, payment         │           │
                              │   └─────┬───────────────┬──────┘           │
                              │         │sync (synchronous_standby_names)  │
                              │         │              │async (recovery)   │
                              │   ┌─────▼─────┐   ┌─────▼─────────────┐    │
                              │   │ Sync      │   │ Async DR replica  │    │
                              │   │ replica   │   │ Abuja AZ-X        │    │
                              │   │ Lagos AZ-B│   │ (cold DR, no app) │    │
                              │   │ (read for │   └───────────────────┘    │
                              │   │ billing)  │                            │
                              │   └─────┬─────┘                            │
                              │         │                                  │
                              │   ┌─────▼──────────────────────────────┐  │
                              │   │ Read replica (AP) — Lagos AZ-C      │  │
                              │   │ Offloads analytics + reporting      │  │
                              │   │ queries from the primary            │  │
                              │   └─────────────────────────────────────┘  │
                              │                                             │
                              │   ┌─────────────────────────────────────┐  │
                              │   │  MongoDB replica set (CP for writes)│  │
                              │   │  Lagos AZ-A primary (progress_notes)│  │
                              │   │  + 2 secondaries (Lagos AZ-B, ABJ)  │  │
                              │   │  writeConcern 'majority' for safety │  │
                              │   └─────────────────────────────────────┘  │
                              │                                             │
                              │   ┌─────────────────────────────────────┐  │
                              │   │  Object storage (encrypted at rest) │  │
                              │   │  Lagos — instructor-uploaded videos │  │
                              │   │  KMS-managed keys, residency = NG   │  │
                              │   └─────────────────────────────────────┘  │
                              │                                             │
                              │   ┌─────────────────────────────────────┐  │
                              │   │  Audit log (append-only, WORM)      │  │
                              │   │  All access to children's PII logged│  │
                              │   └─────────────────────────────────────┘  │
                              └─────────────────────────────────────────────┘

   Cross-border: NONE. All SplashPoint personal data stays in Nigeria.
   Backups: encrypted, in-Nigeria; daily snapshots retained 30 days.
```

---

## 3. CAP theorem placement

SplashPoint has multiple data stores with different CAP choices:

| Subsystem | C | A | P | Rationale |
| --- | --- | --- | --- | --- |
| Booking & payment (PostgreSQL primary + sync replica) | **strong** | lowered | tolerant | A lost enrolment or payment is unacceptable — sync replica means the primary waits for the replica's ACK before COMMIT. If the sync replica is unreachable, the primary refuses writes (CP). |
| Analytics (PostgreSQL read replica, async) | eventual | **high** | tolerant | Reports can tolerate a few seconds of staleness. Async replica keeps serving reads even if the primary is unreachable (AP). |
| Disaster recovery (PostgreSQL async replica, Abuja) | eventual | high | tolerant | Cold DR — promoted only if Lagos AZ-A fails. May lose the last few committed transactions (RPO ~5s, RTO ~15min). |
| Progress notes (MongoDB replica set, writeConcern 'majority') | **strong** | majority-tolerant | tolerant | Skill assessments must not be lost; majority writeConcern guarantees a write is durable on at least 2 of 3 nodes before ack. |

The overall system is **CP for the money** (booking, payment, scheduling) and **AP for analytics** (read replica, async DR). This is a deliberate trade-off: we accept lower write throughput on the primary (sync replica adds latency) in exchange for never losing a payment.

---

## 4. Sync vs async replication trade-offs

| Aspect | Sync (synchronous_standby_names) | Async (default) |
| --- | --- | --- |
| **Write latency** | Higher — primary waits for replica ACK | Lower — primary commits immediately |
| **Durability guarantee** | Strong — a committed write is on at least 2 nodes | Eventual — a committed write is on the primary; replica catches up |
| **RPO** (data loss on primary failure) | 0 (no committed writes lost) | > 0 (last few seconds of writes may be lost) |
| **RTO** (time to failover) | Seconds — promote the sync replica | Seconds to minutes — promote the async replica |
| **Throughput** | Lower (latency-bound) | Higher |
| **Behaviour when replica is down** | Primary blocks writes (CP) | Primary keeps accepting writes (AP) |
| **Network requirement** | Low latency between primary and replica (same AZ ideally) | Can tolerate higher latency (cross-region OK) |
| **Use case** | Money, scheduling, anything you cannot afford to lose | Analytics, DR, cross-region read replicas |

**SplashPoint's choice:** sync replica in Lagos AZ-B (within-region, low latency, <2ms RTT) for the booking/payment/scheduling data; async replica in Abuja AZ-X (cross-region, ~30ms RTT) for disaster recovery; async read replica in Lagos AZ-C for analytics.

---

## 5. Extra protection for children's personal data (NDPA s. 31)

Children are the majority of SplashPoint's customers (toddlers, children, teens). NDPA 2023 s. 31 requires consent from a parent or guardian, purpose limitation, and minimisation. Our additional measures:

1. **Guardian consent record.** The `guardian` table (Portfolio 1) records the consenting adult and their relationship. The `enrol_swimmer()` function refuses to enrol an under-18 swimmer whose `guardian_id` is null (the trigger `trg_swimmer_guardian`).

2. **Column-level encryption** for the most sensitive fields:
   - `guardian.phone`, `guardian.email` — encrypted with `pgcrypto` using a key from the cloud KMS.
   - `swimmer.phone`, `swimmer.email` — same.
   - Plain-text access requires a separate role (`pii_reader`) granted only to the front-desk app and the safeguarding officer.

3. **Role-based access:**
   - `app_booking` — can INSERT enrolments/payments, SELECT non-PII columns. Cannot read guardian phone/email.
   - `app_instructor` — can SELECT swimmer first_name/last_name/dob and progress notes; cannot read payment.amount or guardian contact info.
   - `app_finance` — can SELECT payment rows; cannot read swimmer PII.
   - `pii_reader` (safeguarding officer only) — can decrypt guardian contact info; every SELECT is logged.
   - `analytics_ro` — read-only on the read replica, PII columns replaced by a view that returns NULL for encrypted fields.

4. **Audit logging.** Every access to a row containing a child's PII is logged in an append-only audit table (`audit.child_pii_access`). The log is itself replicated to the DR site.

5. **Retention limits:**
   - Adult swimmer data: retained 5 years after the last enrolment, then anonymised.
   - Child swimmer data: retained 3 years after the child's 18th birthday (or 5 years after last enrolment, whichever is shorter), then deleted. Deletion is a quarterly batch job.
   - Progress notes (MongoDB): same retention as the swimmer; deleted with the swimmer.
   - Payment records: 7 years (tax / financial regulations).
   - Audit logs: 7 years.

6. **Breach response.** Per NDPA s. 40, a breach affecting children's data is reported to the NDPC within 72 hours, and the guardians of every affected child are told without delay. SplashPoint's runbook defines the roles, the comms templates, and the forensic steps.

7. **No profiling or automated decisions** about children. SplashPoint does not use children's data for marketing, recommendations, or pricing decisions. The progress-notes aggregation in Portfolio 4 is for *instructor performance and curriculum review*, not for profiling individual children.

---

## 6. Cloud deployment (managed services)

In production we would use **managed PostgreSQL** (e.g. a Nigeria-region offering from a cloud provider with a Lagos data centre) and **managed MongoDB** (Atlas in a Nigeria region, or self-hosted on Nigerian IaaS). Benefits:

- Automated backups (point-in-time recovery to within 5 minutes).
- Automated failover (managed promote on primary failure).
- Patching and version upgrades handled by the provider.
- Encryption at rest (KMS-managed keys, residency = Nigeria).
- VPC peering to the application tier; no public internet exposure for the database.

If a managed Lagos-region PostgreSQL is not available from the chosen provider, the fallback is **self-hosted PostgreSQL on Nigerian IaaS** (e.g. a Lagos data centre of a Nigerian cloud provider or a co-location facility), with the same replication setup as in `replica_setup.sh`.

---

## 7. What this Portfolio 5 deliverable proves

- **Partitioning:** `lesson_session` is range-partitioned by month; the planner prunes partitions on date-range queries (screenshot of `EXPLAIN` showing only one child scanned).
- **Replication:** a streaming read replica is running on port 5433; it accepts SELECTs and rejects INSERTs; new rows on the primary appear on the replica within milliseconds.
- **Cloud architecture:** a written architecture that places data in Nigerian AZs, picks CAP positions per subsystem, picks sync vs async per data flow, and adds specific protections for children's personal data per NDPA 2023 s. 31.

---

## 8. References

1. Federal Republic of Nigeria, *Nigeria Data Protection Act 2023*.
2. Nigeria Data Protection Commission — https://ndpc.gov.ng/
3. PostgreSQL 16 documentation, Part VII. "Internal Interfaces" — replication, partitioning.
4. MongoDB 8 manual — Replication, Sharding.
5. Eric Brewer, *Towards Robust Distributed Systems* (PODC 2000 keynote) — the CAP theorem.
6. Gilbert & Lynch, *Brewer's Conjecture and the Feasibility of Consistent, Available, Partition-Tolerant Web Services* (SIGACT News 2002).
