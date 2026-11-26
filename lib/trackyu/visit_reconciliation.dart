// Production reconciliation for server snapshots and durable offline visit records.
typedef VisitRecord = Map<String, dynamic>;

VisitRecord normalizeVisit(VisitRecord r) {
  final out = Map<String, dynamic>.from(r);
  void alias(String target, List<String> sources) {
    if (out[target] != null) return;
    for (final s in sources) {
      if (out[s] != null) {
        out[target] = out[s];
        return;
      }
    }
  }
  alias('id', ['Id', 'serverId', 'ServerId']);
  alias('serverId', ['id', 'Id', 'ServerId']);
  alias('requestId', ['RequestId']);
  alias('closeRequestId', ['CloseRequestId']);
  alias('kind', ['Kind']);
  alias('retailerId', ['RetailerId']);
  alias('shopName', ['ShopName', 'PlaceName', 'clientName']);
  alias('placeName', ['PlaceName', 'shopName', 'ShopName']);
  alias('address', ['Address']);
  alias('workDate', ['WorkDate']);
  alias('checkInUtc', ['CheckInUtc']);
  alias('checkOutUtc', ['CheckOutUtc', 'outUtc', 'checkoutUtc']);
  alias('earliestCheckoutUtc', ['EarliestCheckoutUtc']);
  alias('remark', ['Remark']);
  alias('orderRemark', ['OrderRemark']);
  alias('otherRemark', ['OtherRemark']);
  alias('ownerName', ['OwnerName']);
  alias('mobile', ['Mobile']);
  alias('lead', ['Lead']);
  alias('version', ['Version']);
  return out;
}

bool sameVisit(VisitRecord a, VisitRecord b) {
  final requestA = (a['requestId'] ?? a['RequestId'])?.toString();
  final requestB = (b['requestId'] ?? b['RequestId'])?.toString();
  if (requestA != null && requestA.isNotEmpty && requestA == requestB) return true;

  final closeA = (a['closeRequestId'] ?? a['CloseRequestId'])?.toString();
  final closeB = (b['closeRequestId'] ?? b['CloseRequestId'])?.toString();
  if (closeA != null && closeA.isNotEmpty && closeA == closeB) return true;

  final aIds = [a['id'], a['Id'], a['serverId'], a['ServerId'], a['localId']]
      .where((v) => v != null && '$v' != '0' && '$v' != 'null')
      .map((v) => v.toString())
      .toSet();
  if ([b['id'], b['Id'], b['serverId'], b['ServerId'], b['localId']]
      .any((v) => v != null && '$v' != '0' && '$v' != 'null' && aIds.contains(v.toString()))) {
    return true;
  }

  // Explicit distinct operation identities are different visits, even to the same shop.
  if (requestA != null && requestA.isNotEmpty && requestB != null && requestB.isNotEmpty) return false;
  final inA = DateTime.tryParse('${a['checkInUtc'] ?? a['CheckInUtc'] ?? ''}');
  final inB = DateTime.tryParse('${b['checkInUtc'] ?? b['CheckInUtc'] ?? ''}');
  if (inA == null || inB == null || !inA.isAtSameMomentAs(inB)) return false;

  // Same shop name or retailer ID and work date fallback
  final shopA = (a['shopName'] ?? a['ShopName'] ?? a['clientName'])?.toString().trim().toLowerCase();
  final shopB = (b['shopName'] ?? b['ShopName'] ?? b['clientName'])?.toString().trim().toLowerCase();
  final dateA = (a['workDate'] ?? a['WorkDate'])?.toString().split('T')[0].trim();
  final dateB = (b['workDate'] ?? b['WorkDate'])?.toString().split('T')[0].trim();
  if (shopA != null && shopA.isNotEmpty && shopA == shopB && dateA != null && dateA.isNotEmpty && dateA == dateB) {
    return true;
  }

  final retA = (a['retailerId'] ?? a['RetailerId'])?.toString().trim();
  final retB = (b['retailerId'] ?? b['RetailerId'])?.toString().trim();
  if (retA != null && retA.isNotEmpty && retA == retB && dateA != null && dateA.isNotEmpty && dateA == dateB) {
    return true;
  }

  return false;
}

bool visitClosed(VisitRecord row) {
  final out = row['checkOutUtc'] ?? row['CheckOutUtc'] ?? row['outUtc'] ?? row['checkoutUtc'];
  return out != null && '$out'.isNotEmpty && '$out' != 'null';
}

bool regularVisitRequiresServer(VisitRecord row) =>
    '${row['kind'] ?? row['Kind'] ?? ''}'.trim().toLowerCase() == 'regular' ||
    (row['isLegacy'] == true && '${row['kind'] ?? row['Kind'] ?? ''}'.trim().isEmpty) ||
    (row['retailerId'] != null && '${row['retailerId']}'.trim().isNotEmpty);

bool unconfirmedRegularVisit(VisitRecord row) => regularVisitRequiresServer(row) &&
    row['syncState'] != 'synced' && row['checkoutAcknowledged'] != true &&
    (row['isOffline'] == true || row['syncState'] == 'pending' || row['syncState'] == 'blocked');

bool queuedRegularVisit(VisitRecord item) => item['body'] is Map &&
    regularVisitRequiresServer(Map<String, dynamic>.from(item['body'] as Map));

bool visitPending(VisitRecord row) => row['syncState'] == 'pending' || row['syncState'] == 'blocked' ||
    (row['isOffline'] == true && row['syncState'] != 'synced');

List<VisitRecord> mergePendingVisits(List<VisitRecord> remote, List<VisitRecord> local) {
  final result = remote.map(normalizeVisit).toList();
  for (final rawRow in local) {
    final row = normalizeVisit(rawRow);
    final index = result.indexWhere((r) => sameVisit(r, row));
    if (index < 0) {
      if (visitPending(row) || row['localCheckout'] == true) result.add(row);
      continue;
    }
    final server = result[index];
    if (visitClosed(server)) {
      result[index] = normalizeVisit({
        ...row,
        ...server,
        'isOffline': false,
        'syncState': 'synced',
      });
      continue;
    }
    // Closing is monotonic for a visit identity. An older open snapshot cannot
    // resurrect a locally persisted checkout, even after its outbox receipt.
    if (visitClosed(row) && !visitClosed(server)) {
      result[index]=normalizeVisit({...server,...row,
        if(server['id']!=null)'id':server['id'],
        if(server['id']!=null)'serverId':server['id'],
        if(server['version']!=null)'version':server['version'],
      });
      continue;
    }
    // Preserve unsynced departure and inline media; use the server's canonical identity/version.
    result[index] = normalizeVisit(visitPending(row) ? {
      ...server, ...row,
      if (server['id'] != null) 'id': server['id'],
      if (server['id'] != null) 'serverId': server['id'],
      if (server['version'] != null) 'version': server['version'],
      if (visitClosed(server)) 'checkOutUtc': server['checkOutUtc'] ?? server['CheckOutUtc'],
      'localId': row['localId'] ?? row['id'],
    } : {...row, ...server});
  }
  return result;
}

int checkoutVisitIndex(List<VisitRecord> rows, Object? targetId) {
  if (targetId != null) {
    return rows.indexWhere((r) => [r['id'], r['Id'], r['localId'], r['serverId'], r['ServerId']]
        .any((id) => id != null && id.toString() == targetId.toString()));
  }
  final open = rows.indexed.where((r) => !visitClosed(r.$2)).toList();
  return open.length == 1 ? open.single.$1 : -1;
}
