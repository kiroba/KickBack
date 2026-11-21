/// ============================================================================
/// OMNI NODE WIRING — the standard node-handoff layer (SoT §9).
/// Canary: KickBack (K1 landed the layer, K2 routes the publish path).
/// Proven here, it lifts into Omni-Core-UI at K3
/// (Kiro's ruling, Nov 20, 2026) so LPE and OmniCast inherit the same layer.
///
/// What this is: one door out of the app, in two modes.
/// - Delegate: a node answered the loopback probe, so the node sequences,
///   signs, stores and relays. The app hands it action + payload ONLY —
///   the daemon chains at append inside its write lock (sets previous_hash
///   itself, signs with the node key; POST /api/events/append returns
///   event_id + merkle_hash). No local chain, no client-supplied
///   previous_hash, no sequence field: ordering IS previous_hash
///   (SoT §15 ruling, Nov 20, 2026).
/// - Standalone: no node answered. The app signs into its own on-device
///   log (LocalEventStore) and syncs to a hub when one appears.
///
/// appContext is LOCAL ONLY: it names this app for this device's own
/// filtering and logging. It is never serialized into an envelope or an
/// HTTP body (working assumption A; putting it on the wire needs a ruling).
///
/// Claude's v3 draft carried OmniSigner / OmniLocalWal / OmniChainHead
/// abstractions. They collapse onto what Omni-Core-UI already ships:
/// LocalEventStore signs and stores, OmniHubClient probes and appends,
/// and OmniChainHead does not exist — there is no chain-head endpoint.
/// ============================================================================
import 'package:flutter/foundation.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

/// Delegate: a node answered the probe and sequences/signs/relays for us.
/// Standalone: no node answered; the app keeps its own signed log.
enum OmniNodeMode { delegate, standalone }

/// Connection state for the UI, under the Honest UI wording of record
/// (SoT §3): the interface states only what is true right now, and tests,
/// stubs and offline fallbacks are labeled in plain words.
enum OmniUiStatus {
  notChecked,
  connected,
  unauthorized,
  forbidden,
  unreachable,
  error,
}

/// The result of one loopback probe. Local only — never sent anywhere.
class NodeProbeResult {
  final OmniNodeMode mode;
  final OmniUiStatus uiStatus;
  final String statusMessage;
  final String? daemonVersion;
  final String? nodeId;
  final int peerCount;

  const NodeProbeResult({
    required this.mode,
    required this.uiStatus,
    required this.statusMessage,
    this.daemonVersion,
    this.nodeId,
    required this.peerCount,
  });
}

class OmniNodeWiring {
  OmniNodeWiring({
    required this.appContext,
    required this.store,
    required this.hub,
  });

  /// Which app this is ('kickback'). Local only — see the header note.
  final String appContext;

  /// The app's signed on-device log (standalone mode + sync source).
  final LocalEventStore store;

  /// The hub this app currently talks to. Replaced when the user changes
  /// the Hub setting, exactly as the app's own client is.
  OmniHubClient hub;

  OmniNodeMode mode = OmniNodeMode.standalone;
  final ValueNotifier<OmniUiStatus> uiStatus =
      ValueNotifier<OmniUiStatus>(OmniUiStatus.notChecked);
  bool isInitialized = false;
  NodeProbeResult? lastProbe;

  /// First probe at startup. Never throws (the client's probe never does).
  Future<NodeProbeResult> initializeNode() async {
    final result = await probe();
    isInitialized = true;
    return result;
  }

  /// Asks the node-health telemetry whether a node is really there and
  /// records the honest answer as this wiring's mode + UI status.
  Future<NodeProbeResult> probe() async {
    final conn = await hub.connection();
    final mapped = switch (conn.state) {
      HubConnectionState.connected => OmniUiStatus.connected,
      HubConnectionState.unauthorized => OmniUiStatus.unauthorized,
      HubConnectionState.forbidden => OmniUiStatus.forbidden,
      HubConnectionState.unreachable => OmniUiStatus.unreachable,
      HubConnectionState.error => OmniUiStatus.error,
    };
    mode = conn.connected ? OmniNodeMode.delegate : OmniNodeMode.standalone;
    uiStatus.value = mapped;
    final result = NodeProbeResult(
      mode: mode,
      uiStatus: mapped,
      statusMessage: conn.connected
          ? 'Node answered at ${hub.address}.'
          : (conn.detail ?? 'No node answered; running standalone.'),
      daemonVersion: conn.status.version,
      nodeId: conn.status.nodeId,
      peerCount: conn.status.peers,
    );
    lastProbe = result;
    return result;
  }

  /// Delegate append: action + payload only. The daemon sets previous_hash
  /// and signs; the reply carries event_id + merkle_hash. (K2 routes
  /// KickBack's posting through this; K1 routes nothing yet.)
  Future<Map<String, dynamic>?> appendToNode(
          String action, Map<String, dynamic> payload) =>
      hub.appendEvent(action, payload);

  /// Standalone append: sign into this device's own log.
  Future<OmniEvent> appendLocal(
          String action, Map<String, dynamic> payload) =>
      store.append(action, payload);

  /// The publish path (K2): sign into the local log, then hand what is
  /// waiting to the node. The app's signature travels inside the event;
  /// the node re-signs as itself and relays. Returns the stored event
  /// and the sync outcome, in the order the app already used them.
  Future<(OmniEvent, HubSyncResult)> publish(
      String action, Map<String, dynamic> payload) async {
    final event = await appendLocal(action, payload);
    final sync = await syncToNode();
    return (event, sync);
  }

  /// Hands everything still waiting in the local log to the hub.
  Future<HubSyncResult> syncToNode() => store.syncToHubDetailed(hub);

  /// The daemon's event feed, through the same client the wiring probes.
  Future<HubFeedResult> feed(
          {int limit = 50, int? before, int? since, String? type}) =>
      hub.eventsFeed(limit: limit, before: before, since: since, type: type);

  void dispose() => uiStatus.dispose();
}
