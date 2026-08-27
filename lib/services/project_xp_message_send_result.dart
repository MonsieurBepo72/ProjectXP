enum ProjectXpMessageSendStatus {
  sent,
  blocked,
  error,
}

class ProjectXpMessageSendResult {
  const ProjectXpMessageSendResult._(
    this.status,
  );

  final ProjectXpMessageSendStatus status;

  bool get sent =>
      status == ProjectXpMessageSendStatus.sent;

  bool get blocked =>
      status == ProjectXpMessageSendStatus.blocked;

  bool get failed =>
      status == ProjectXpMessageSendStatus.error;

  static const ProjectXpMessageSendResult success =
      ProjectXpMessageSendResult._(
    ProjectXpMessageSendStatus.sent,
  );

  static const ProjectXpMessageSendResult denied =
      ProjectXpMessageSendResult._(
    ProjectXpMessageSendStatus.blocked,
  );

  static const ProjectXpMessageSendResult failure =
      ProjectXpMessageSendResult._(
    ProjectXpMessageSendStatus.error,
  );
}
