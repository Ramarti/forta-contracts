// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// These are the roles used in the components of the Forta system, except
// Forta token itself, that needs to define it's own roles for consistency accross chains

bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

// Routing
bytes32 constant ROUTER_ADMIN_ROLE  = keccak256("ROUTER_ADMIN_ROLE");
// Base component
bytes32 constant ENS_MANAGER_ROLE   = keccak256("ENS_MANAGER_ROLE");
bytes32 constant UPGRADER_ROLE      = keccak256("UPGRADER_ROLE");
// Registries
bytes32 constant AGENT_ADMIN_ROLE   = keccak256("AGENT_ADMIN_ROLE");
bytes32 constant SCANNER_ADMIN_ROLE = keccak256("SCANNER_ADMIN_ROLE");
bytes32 constant DISPATCHER_ROLE    = keccak256("DISPATCHER_ROLE");
// Staking
bytes32 constant SLASHER_ROLE       = keccak256("SLASHER_ROLE");
bytes32 constant SWEEPER_ROLE       = keccak256("SWEEPER_ROLE");
bytes32 constant REWARDS_ADMIN      = keccak256("REWARDS_ADMIN_ROLE");
// Scanner Node Vesion
bytes32 constant SCANNER_VERSION_ROLE = keccak256("SCANNER_VERSION_ROLE");