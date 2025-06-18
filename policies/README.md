# Ghaf Policy Repository

This repository is the central location for storing [Open Policy Agent (OPA)](https://www.openpolicyagent.org/) policies used in the [Ghaf](https://github.com/tiiuae/ghaf) platform. These policies define security and runtime behavior for components managed by Ghaf.

Currently, the repository includes policies for **USB hotplug control**, with more policy types to be added over time.

## 📁 Directory Structure

├── **policies**  

│ ├── **usb_hotplug.rego**                `Rego policy to access USB hotplug rules`  

│ └── **usb_hotplug_rules.json**     `USB hotplug rules`

├── **README.md**

└── **tests**

    ├── **opa_server_eval_tests**
    
    │ └── **test.sh**                               `Script to evaluate Rego using OPA server`
    
    ├── **python_eval_tests**  
    
    │ └── **main.py**                            `Python implementation for local evaluation`
    
    └── **shell.nix**                               `Nix shell environment definition`

## Tests

Two types of policy evaluation tests are included:

### 1. Python-Based Local Evaluation

This is a reference implementation of the USB policy logic in Python. It's useful for local validation and experimentation.

#### To run the Python tests:

```bash
$> cd tests
$> nix-shell
nix-shell $> cd python_eval_tests
nix-shell $> python main.py
```

### 2. OPA Server-Based Evaluation

This test uses an OPA server instance to evaluate the Rego policy with sample inputs.

#### To run the OPA server evaluation tests:

```bash
$> cd tests
$> nix-shell
nix-shell $> cd opa_server_eval_tests
nix-shell $> bash ./test.sh
```

**Note:** Rego policies in this repository are written using Rego v1 syntax.  
Make sure you are using an OPA version that is compatible with Rego v1.



## USB Hotplug Policy

This policy defines rules for securely passing through USB devices to authorized virtual machines (VMs). The core configuration is defined in JSON format, enabling local evaluation. A client can pull the policy and evaluate it locally. When local evaluation is used, the client must implement a mechanism to synchronize the policy with the OPA server.

### Features

- Authorization rules based on USB class, subclass, and protocol
- Global blacklists for specific vendor/product combinations
- Per-VM blacklists to restrict USB devices for individual VMs
- Explicit rules to authorize specific USB devices (by vendor and product ID) to specific VM(s)

### Security Philosophy

The policy follows a whitelist-first approach. By default, a VM is considered unauthorized to access a USB device unless explicitly permitted by a rule. Even if a device is authorized through a general rule, its access can be overridden and denied using VM-specific blacklist entries.



## Roadmap

This repository will expand beyond USB to include policies for:

- Inter-VM communication

- Device access control

- Authentication and authorization
  
  and more.
