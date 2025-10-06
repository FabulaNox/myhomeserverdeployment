Autopsy artifacts
=================

Purpose
-------
This folder is a convenient place to keep prebuilt Sleuth Kit artifacts required by the Autopsy installer so you can deploy Autopsy to other machines without building Sleuth Kit from source.

Files contained here
--------------------
- sleuthkit-4.14.0.jar
- libtsk_jni.so
- sleuthkit-caseuco-4.14.0.jar

Origin
------
These files were copied from the local system's `sleuthkit-java` package and the existing Autopsy installation on the machine where they were prepared. They correspond to Sleuth Kit / sleuthkit-java version 4.14.0.

Usage
-----
The installer will accept either an artifacts directory or explicit paths to the jar and shared object. Examples:

Use the artifacts directory (recommended):

```bash
bash Autopsy/install_application.sh -v -a Autopsy/artifacts
```

Provide explicit paths:

```bash
bash Autopsy/install_application.sh -v -p Autopsy/artifacts/sleuthkit-4.14.0.jar -s Autopsy/artifacts/libtsk_jni.so
```

The installer will copy the jar and the JNI shared library into the Autopsy installation `lib` directory and perform the usual setup steps.

Artifact discovery
------------------
The installer now includes a built-in search routine: if artifacts are not found
in the provided `-a` directory or via explicit `-p/-s` paths, it will search a
small set of common locations (Downloads, HOME, `/usr/share/java`, `/usr/lib*`,
`/opt`, apt cache and `/tmp`) and as a last resort perform a wider filesystem
search. This removes the need for an external wrapper script and keeps the
installer single-file.

Committing binaries
-------------------
Storing binary artifacts in a git repository is convenient but can grow the repo size. Recommended options:

- Use Git LFS for these files (`git lfs track "Autopsy/artifacts/*"`) and commit normally.
- Or keep this folder out of version control by adding `Autopsy/artifacts/` to `.gitignore` and distribute artifacts separately (scp, rsync, or an artifact repository).

Security & licensing
--------------------
These files are third-party (Sleuth Kit). Ensure you comply with their license before redistributing. Do not include secrets in this folder.

Troubleshooting
---------------
- If the installer still reports missing artifacts, re-run:

```bash
dpkg -L sleuthkit-java | grep -E 'tsk_jni.jar|libtsk_jni.so' -n || true
```

and confirm the paths point to the files in this directory or adjust installer flags to the correct paths.

Contact / Notes
----------------
If you want, I can:
- Commit these artifacts using Git LFS and add a short CI-friendly installation note.
- Make the installer tolerant (non-fatal warnings) or add a `--force` flag.

Wrapper script
--------------
If you'd like a small launcher that sets a known Java runtime and library path
before starting Autopsy 4.22, a wrapper script has been added to the repo at
`Autopsy/autopsy-4.22-wrapper.sh`.

To install the wrapper system-wide:

```bash
sudo cp Autopsy/autopsy-4.22-wrapper.sh /usr/local/bin/autopsy-4.22
sudo chmod +x /usr/local/bin/autopsy-4.22
```

This will make `autopsy-4.22` available on the PATH and will start the
installation you created. The wrapper auto-detects the launcher under common
locations (including `/usr/lib/autopsy-4.22.0`, nested layouts, and `/usr/autopsy`).
It sets a controlled `JAVA_HOME` and `LD_LIBRARY_PATH`. Edit the wrapper if you
installed Autopsy to an unusual location or want a different JDK path.

