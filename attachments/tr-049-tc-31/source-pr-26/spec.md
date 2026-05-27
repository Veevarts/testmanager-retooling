# Backfill Manual Runs Specification

## Purpose

Define operator behavior for progressively invoking historical manual analytics runs in safe ordered monthly batches while waiting for each Step Functions execution to finish before starting the next.

## Requirements

### Requirement: Org list ingestion and dedupe

The runner MUST accept exactly one subscriber org source: an org file or directly supplied subscriber org IDs. It MUST extract/validate Salesforce org IDs, dedupe them, and report only counts unless explicitly configured otherwise.

#### Scenario: Duplicate org IDs in dry run
- GIVEN an org list file containing duplicate org IDs
- WHEN the runner is executed with `--dry-run`
- THEN it prints the unique org count and total planned batches
- AND it does not call the manual-runs API

#### Scenario: Direct subscriber org IDs
- GIVEN subscriber org IDs are provided through `--subscriber-org-ids` as a string list
- WHEN the runner plans work
- THEN it validates and dedupes the provided IDs
- AND it does not require `--org-file`

#### Scenario: Multiple org sources are rejected
- GIVEN both `--org-file` and `--subscriber-org-ids` are provided
- WHEN the runner starts
- THEN it fails with a clear validation error
- AND no API or AWS call is attempted

### Requirement: Date range and period ordering

The runner MUST accept inclusive start and end dates, derive monthly periods, and order them according to the operator-selected order.

#### Scenario: Recent data first
- GIVEN `--start-date 2016-01-01`, `--end-date 2026-05-26`, and `--order newest-first`
- WHEN the runner plans work
- THEN planned periods start with `2026-05` and move backward
- AND each API payload contains exactly one monthly period

#### Scenario: Invalid date arguments
- GIVEN invalid dates, an unknown order, or an end date before the start date
- WHEN the runner starts
- THEN it fails with a clear validation error
- AND no API or AWS call is attempted

### Requirement: Sequential execution with Step Functions wait

The runner MUST NOT start the next manual run until the previous execution ARN reaches a terminal Step Functions status via `DescribeExecution`.

#### Scenario: Wait before next start
- GIVEN two planned work items and the first API call returns execution ARN `arn:one`
- WHEN `DescribeExecution(arn:one)` is `RUNNING`
- THEN no second API call is made
- AND the runner polls until `SUCCEEDED`, `FAILED`, `TIMED_OUT`, or `ABORTED`

#### Scenario: Terminal failure is recorded
- GIVEN `DescribeExecution` returns `FAILED`, `TIMED_OUT`, or `ABORTED`
- WHEN the wait completes
- THEN the progress file records the terminal status and failure details
- AND the next behavior follows the configured failure policy

### Requirement: Resume-safe progress

The runner MUST persist progress per month/batch and use the resume file to skip completed successful work.

#### Scenario: Successful execution is recorded
- GIVEN the manual-runs API returns an execution ARN and Step Functions returns `SUCCEEDED`
- WHEN a work item completes
- THEN progress includes period, org batch identity, execution ARN, status, start/stop timestamps, and poll metadata

#### Scenario: Resume skips completed batches
- GIVEN a resume file with completed `SUCCEEDED` records
- WHEN the runner is started with that resume file
- THEN those records are skipped
- AND pending, failed, or incomplete records remain eligible according to the retry policy

### Requirement: Secret and credential safety

The runner MUST read API credentials and AWS credentials from environment/default AWS provider chain and MUST NOT print or persist secrets.

#### Scenario: Credentials are provided
- GIVEN an API key and AWS credentials are available
- WHEN the runner logs progress or writes the resume file
- THEN API key, AWS secret key, and session token values are absent from stdout, stderr, and progress JSON
