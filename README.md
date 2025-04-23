# OpenAI Codex CLI + BadPirate

This is a fork of the [OpenAI Codex CLI](https://github.com/openai/codex). For details about the original Codex CLI, its features, and usage, please refer to the [main repository](https://github.com/openai/codex).

## About This Fork

This fork introduces enhancements on the `badpirate` branch, focusing on **"Unlocking Container Agent"** capabilities. The goal is to enable a truly **Full Auto** agent that can:

- Run Docker containers for setting up and utilizing end-to-end tests.
- Install packages from npm without being blocked by a firewall.
- Provide a more flexible and powerful sandboxing mechanism for agent autonomy.

### Key Differences in Usage

The `run_in_container.sh` script has been enhanced with additional flags to provide more flexibility and control over containerized workflows. Below are the new flags and their purposes:

#### Additional Flags

- `--dangerously-allow-network-outbound`
  - Allows unrestricted outbound network traffic inside the container.
  - Use with caution as it bypasses the firewall restrictions.

- `--dangerously-allow-sudo`
  - Enables sudo execution inside the container via the `sudonode` user.
  - Useful for workflows requiring elevated privileges.

- `--dangerously-allow-install`
  - Combines the effects of `--dangerously-allow-network-outbound` and `--dangerously-allow-sudo`.
  - Also enables Docker-in-Docker (nested Docker daemon).

- `--allow-docker-in-docker`
  - Enables Docker-in-Docker by running the container in privileged mode and starting a nested Docker daemon.

- `--notify`
  - A flag for codex rather than run_in_container.sh, already exists on main, but on my build it will do two "beeps" when it requires your attention and on a non-mac machine. Because container is always on linux, this gives you a heads up that your agent is done. About as flaky as the main branch version but what are you gonna do?

#### Examples of Usage

1. Run a simple command inside the container:
   ```bash
   ./run_in_container.sh "echo Hello, world!"
   ```

2. Allow unrestricted outbound network traffic and sudo execution:
   ```bash
   ./run_in_container.sh --dangerously-allow-install --work_dir /path/to/project "npm install"
   ```

3. Enable Docker-in-Docker and list running containers:
   ```bash
   ./run_in_container.sh --allow-docker-in-docker "docker ps"
   ```

### How to Use a Non-Locked Down Containerized AI

1. Clone this repository and switch to the `badpirate` branch:
   ```bash
   git clone https://github.com/badpirate/codex.git
   cd codex
   git checkout badpirate
   ```

2. Build the container:
   ```bash
   ./codex-cli/scripts/build_container.sh
   ```

3. Run the container with the desired flags:
   ```bash
   ./codex-cli/scripts/run_in_container.sh --dangerously-allow-install --allow-docker-in-docker
   ```

### Why Use This Fork?

This fork is ideal for developers who need:

- A more autonomous agent capable of running complex workflows, including end-to-end tests.
- The ability to install dependencies and execute commands without being blocked by restrictive firewalls.
- Enhanced security and sandboxing for running commands in a controlled environment.

---

For any questions or contributions, feel free to open an issue or pull request. Happy hacking! 🚀
