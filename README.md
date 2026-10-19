# Windows Event-Driven Backup Pipeline

Automated, fault-tolerant local backup system using native Windows Batch, Robocopy, and Task Scheduler. 

Designed to operate unattended on workstations with removable external storage, eliminating silent failures, schedule drift, and disk thrashing when target disks are unmounted during scheduled runs.

## Architecture & Mechanics

* **State-Machine Orchestration:** Consolidates daily differentials and weekly archival into a single sequential pipeline (`backup_engine.bat`). Daily mirror executes first; weekly snapshots only evaluate upon clean mirror completion, preventing Robocopy self-collisions.
* **Dual-Trigger Execution:** Combines a daily 03:00 AM calendar schedule with Windows Event Subscriptions (Event ID 98: NTFS volume mount). If the backup volume is disconnected during scheduled execution, the engine catches up the moment the drive is plugged in.
* **Self-Healing Weekly Catch-Up:** Evaluates calendar week boundaries (`%U`). If the machine is powered off across a weekend, the next daily execution detects the missing weekly flag and archives the environment immediately.
* **Idempotency & Maintenance Suppression:** Uses date-stamped and week-stamped flags (`flag_YYYY-MM-DD.txt`, `flag_week_YYYY_WW.txt`) to prevent duplicate executions. Suppresses false-positive volume health triggers (NTFS Event 98) between 00:00 and 03:00 if the previous day's backup succeeded, protecting the scheduled 03:00 run from midnight maintenance preemption.
* **Dead Man's Switches:** Validates source directory structure prior to mirror operations to prevent wiping destinations during partial mounts.
* **Process Interlocking:** Inspects running hypervisor processes (`tasklist` for VirtualBox, VMware, Hyper-V) before initiating virtual machine backups.
* **FIFO Retention:** Weekly archive maintains an automated rolling retention window (retains the newest 4 snapshots, purges older directories).

## Directory Structure

```text
<BACKUP_DRIVE>:\System_Backup\
├── Live_Mirror\              # Tier 1: Daily 1:1 mirror (UserProfile, VMs)
├── mirror_log.txt            # Prepend run log for daily syncs
├── flag_YYYY-MM-DD.txt       # Daily idempotency lock
└── Archive\                  # Tier 2: Weekly historical archives
    ├── YYYY-MM-DD\           # Snapshot point-in-time directories
    ├── archive_log.txt       # Archive-specific execution log
    └── flag_week_YYYY_WW.txt # Weekly idempotency lock
```

## Components

* `backup_engine.bat`: Unified sequential runner managing drive validation, daily mirror sync, and weekly FIFO archives.
* `Backup_Engine.xml`: Consolidated Task Scheduler definition (NTFS mount triggers, SYSTEM context, RTC wake-to-run, and missed-execution catch-up).

## Prerequisites & Caveats

* **Script Path Hardcoding:** `Backup_Engine.xml` defaults to `C:\BackupScripts\`. If deploying to a different folder, update the `<Command>` and `<WorkingDirectory>` tags in the XML prior to importing.
* **Dynamic Target Resolution:** The backup engine and XML event trigger automatically scan mounted volumes (`D:` through `Z:`) for the root `\System_Backup\` directory. No drive letter manual configuration is required.
* **Power & Wake Timers:** For unattended execution from sleep, ensure **Allow wake timers** is set to **Enabled** under Windows Advanced Power Options. Timed calendar triggers can assert RTC wake; Event ID triggers fire only while the host is awake.
* **Task History:** Enable **All Tasks History** in the Task Scheduler Actions pane to maintain an event log trail in Event Viewer under `Applications and Services Logs > Microsoft > Windows > TaskScheduler > Operational`.

## Setup & Deployment

1. Clone or copy repository files to `C:\BackupScripts\`.
2. Ensure your external storage contains a root folder named `System_Backup`.
3. Open `backup_engine.bat` and update configuration variables at the top (replace `<YOUR_USERNAME>` with your Windows user folder name, and adjust VM or exclusion paths as needed).
4. Import the task via an elevated Command Prompt:
   ```cmd
   schtasks /create /xml "C:\BackupScripts\Backup_Engine.xml" /tn "Backup_Engine" /f
   ```
5. Verify the task is configured to run under `NT AUTHORITY\SYSTEM` with highest privileges.

## License

This project is released under the [0BSD License](LICENSE).