import 'package:boardhop/data/models/work_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const descriptor = 'aad.YTM2YTFjNWEtOGJmMy03MWNmLWIyMzEtMDllYWM5MGI3YWRk';
  const avatar =
      'https://dev.azure.com/puremedia/_apis/GraphProfile/MemberAvatars/$descriptor';

  test('a reviewer without a descriptor still reaches the Graph avatar', () {
    // Spike s23: reviewers carry no `descriptor`, only the avatar link.
    final reviewer = IdentityRef.fromJson({
      'displayName': 'Denis Fruža',
      'id': 'a36a1c5a-8bf3-61cf-b231-09eac90b7add',
      'imageUrl':
          'https://dev.azure.com/puremedia/_api/_common/identityImage?id=a36a',
      'vote': 0,
      '_links': {
        'avatar': {'href': avatar},
      },
    });
    expect(reviewer.descriptor, descriptor);
    expect(reviewer.org, 'puremedia');
    final source = reviewer.avatarSource();
    expect(source, isNotNull);
    expect(source!.isGraph, isTrue, reason: 'the url form 401s with Entra');
    expect(source.descriptor, descriptor);
  });

  test('an explicit descriptor still wins', () {
    final author = IdentityRef.fromJson({
      'displayName': 'Javier Perez',
      'descriptor': descriptor,
      'imageUrl': avatar,
      '_links': {
        'avatar': {'href': avatar},
      },
    });
    expect(author.descriptor, descriptor);
    expect(author.avatarSource()!.isGraph, isTrue);
  });

  test('links that are not member avatars are left alone', () {
    expect(IdentityRef.descriptorFromAvatar(null), isNull);
    expect(IdentityRef.descriptorFromAvatar(''), isNull);
    expect(
      IdentityRef.descriptorFromAvatar('https://example.com/a/b.png'),
      isNull,
    );
    expect(
      IdentityRef.descriptorFromAvatar(
        'https://dev.azure.com/o/_apis/GraphProfile/MemberAvatars',
      ),
      isNull,
    );
    // A stranger with only the legacy link keeps falling back to initials.
    final legacy = IdentityRef.fromJson({
      'displayName': 'No Links',
      'imageUrl': 'https://dev.azure.com/o/_api/_common/identityImage?id=1',
    });
    expect(legacy.descriptor, isNull);
    expect(legacy.avatarSource()!.isGraph, isFalse);
  });
}
