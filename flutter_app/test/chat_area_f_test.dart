import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/chat.dart';
import 'package:dyadespace/models/day_report.dart';
import 'package:dyadespace/models/notification_item.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/services/chat_media_service.dart';
import 'package:dyadespace/services/chat_service.dart';
import 'package:dyadespace/services/progress_share.dart';
import 'package:dyadespace/utils/toronto_time.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contentTypeFor (audit fix: gif/webp/webm)', () {
    test('gif, webp and webm map to their MIME types', () {
      expect(ChatMediaService.contentTypeFor('a.gif'), 'image/gif');
      expect(ChatMediaService.contentTypeFor('a.webp'), 'image/webp');
      expect(ChatMediaService.contentTypeFor('a.webm'), 'video/webm');
    });

    test('existing mappings are unchanged', () {
      expect(ChatMediaService.contentTypeFor('a.jpg'), 'image/jpeg');
      expect(ChatMediaService.contentTypeFor('a.png'), 'image/png');
      expect(ChatMediaService.contentTypeFor('a.mp4'), 'video/mp4');
      expect(ChatMediaService.contentTypeFor('a.m4a'), 'audio/mp4');
      expect(ChatMediaService.contentTypeFor('a.xyz'),
          'application/octet-stream');
    });

    test('10 MB cap constant', () {
      expect(ChatMediaService.maxUploadBytes, 10 * 1024 * 1024);
    });
  });

  group('toronto_time (audit fix: client report dates)', () {
    test('winter date is EST (UTC-5)', () {
      // 2026-11-21 12:00 UTC -> 07:00 Toronto, same day.
      expect(torontoDateId(DateTime.utc(2026, 11, 21, 12)), '2026-11-21');
    });

    test('summer date is EDT (UTC-4)', () {
      expect(torontoDateId(DateTime.utc(2026, 7, 1, 12)), '2026-07-01');
    });

    test('early-morning UTC lands on the previous Toronto day', () {
      // 2026-01-01 03:00 UTC -> 2025-12-31 22:00 EST.
      expect(torontoDateId(DateTime.utc(2026, 1, 1, 3)), '2025-12-31');
    });

    test('DST starts the second Sunday of March 2026 (Mar 8)', () {
      expect(torontoDateId(DateTime.utc(2026, 3, 8, 6, 59)), '2026-03-08');
      // 06:59 UTC is still EST (01:59); 07:00 UTC is EDT (03:00).
      expect(torontoOffsetMinutes(DateTime.utc(2026, 3, 8, 6, 59)), -300);
      expect(torontoOffsetMinutes(DateTime.utc(2026, 3, 8, 7)), -240);
    });

    test('DST ends the first Sunday of November 2026 (Nov 1)', () {
      expect(torontoOffsetMinutes(DateTime.utc(2026, 11, 1, 5, 59)), -240);
      expect(torontoOffsetMinutes(DateTime.utc(2026, 11, 1, 6)), -300);
    });
  });

  group('DayReport date (audit fix: no silent now fallback)', () {
    test('derives the date from the doc id when date is missing', () {
      final r = DayReport.fromMap('2026-11-20', {});
      expect(r.date, DateTime(2026, 11, 20));
    });

    test('stored date still wins over the id', () {
      final r = DayReport.fromMap('2026-11-20', {
        'date': Timestamp.fromDate(DateTime(2026, 11, 19)),
      });
      expect(r.date.year, 2026);
      expect(r.date.month, 11);
      expect(r.date.day, 19);
    });
  });

  group('AppNotification reportId (audit fix: report taps)', () {
    test('round-trips reportId from the doc map', () {
      final n = AppNotification.fromMap('n1', {
        'userId': 'u1',
        'title': 't',
        'body': 'b',
        'type': 'dayReport',
        'reportId': '2026-11-20',
        'materialRequestId': 'req1',
      });
      expect(n.reportId, '2026-11-20');
      expect(n.materialRequestId, 'req1');
    });
  });

  group('progress share (audit fix: all statuses)', () {
    test('lists to-confirm, paused and to-do tasks', () {
      const s = AppStrings('en');
      const site = Site(id: 'site1', name: 'Lakeside');
      final tasks = [
        TaskItem(
          id: 't1',
          title: 'Confirm me',
          siteId: 'site1',
          assigneeIds: ['me'],
          createdBy: 'me',
          status: TaskStatus.toConfirm,
        ),
        TaskItem(
          id: 't2',
          title: 'Paused one',
          siteId: 'site1',
          assigneeIds: ['me'],
          createdBy: 'me',
          status: TaskStatus.paused,
        ),
        TaskItem(
          id: 't3',
          title: 'Not started',
          siteId: 'site1',
          assigneeIds: ['me'],
          createdBy: 'me',
          status: TaskStatus.todo,
        ),
      ];
      final text = buildProgressText(s, site, tasks);
      expect(text, contains('Confirm me'));
      expect(text, contains('Paused one'));
      expect(text, contains('Not started'));
      expect(text.contains('No work to report yet.'), isFalse);
    });
  });

  group('ChatService (audit fixes)', () {
    test('sendMessage throws ChatException when the conversation is gone',
        () async {
      final fake = FakeFirebaseFirestore();
      final service = ChatService(db: fake);
      expect(
        () => service.sendMessage(
          conversationId: 'missing',
          senderId: 'me',
          senderName: 'Me',
          text: 'hello',
        ),
        throwsA(isA<ChatException>()),
      );
    });

    test('sendMessage lands when the conversation exists', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('conversations').doc('c1').set(
            const Conversation(
              id: 'c1',
              type: 'dm',
              participantIds: ['me', 'u2'],
              createdBy: 'me',
            ).toMap(),
          );
      final service = ChatService(db: fake);
      await service.sendMessage(
        conversationId: 'c1',
        senderId: 'me',
        senderName: 'Me',
        text: 'hello',
      );
      final msgs =
          await fake.collection('conversations/c1/messages').get();
      expect(msgs.docs, hasLength(1));
      expect(msgs.docs.first.data()['text'], 'hello');
    });

    test('sendBroadcast dedupes recipients and reports the result',
        () async {
      final fake = FakeFirebaseFirestore();
      final service = ChatService(db: fake);
      final result = await service.sendBroadcast(
        senderId: 'me',
        senderName: 'Me',
        recipientIds: ['u2', 'u2', 'u3', 'me'],
        text: 'hi all',
      );
      expect(result.sentIds, hasLength(2));
      expect(result.failedIds, isEmpty);
      expect(result.allSent, isTrue);
      final convs = await fake.collection('conversations').get();
      expect(convs.docs, hasLength(2));
    });

    test('markRead marks more than 100 messages (no 100 cap)', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('conversations').doc('c1').set(
            const Conversation(
              id: 'c1',
              type: 'dm',
              participantIds: ['me', 'u2'],
              createdBy: 'me',
              unreadBy: ['me'],
            ).toMap(),
          );
      final messages = <ChatMessage>[];
      for (var i = 0; i < 150; i++) {
        final id = 'm$i';
        await fake
            .collection('conversations/c1/messages')
            .doc(id)
            .set(ChatMessage(
              id: id,
              senderId: 'u2',
              senderName: 'Other',
              text: 'msg $i',
              readBy: ['u2'],
            ).toMap());
        messages.add(ChatMessage(
          id: id,
          senderId: 'u2',
          senderName: 'Other',
          text: 'msg $i',
          readBy: ['u2'],
        ));
      }
      final service = ChatService(db: fake);
      await service.markRead(
        conversationId: 'c1',
        myId: 'me',
        messages: messages,
      );
      final snap =
          await fake.collection('conversations/c1/messages').get();
      expect(snap.docs, hasLength(150));
      for (final doc in snap.docs) {
        expect((doc.data()['readBy'] as List).contains('me'), isTrue,
            reason: 'message ${doc.id} was not marked read');
      }
    });
  });
}
