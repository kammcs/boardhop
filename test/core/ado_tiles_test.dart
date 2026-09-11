import 'dart:ui' show Color;

import 'package:boardhop/core/util/ado_tiles.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:flutter_test/flutter_test.dart';

Color c(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

void main() {
  group('service tiles (spike s16 samples)', () {
    test('color matches the generated member avatar', () {
      const samples = {
        'DevOps Mobile App': '#001e51',
        'CloudCover 2.0': '#008272',
        'Product': '#aa0000',
        'Special Projects and AI': '#004c1a',
        'puremedia': '#001e51',
        'A': '#004b51',
        'H': '#5d005d',
        'Aa': '#5c2893',
        'Ac': '#004c1a',
        'Kelly Kamm': '#b600a0',
        'kelly kamm': '#32105c',
        'Boardhop Team': '#004c1a',
        'Émile Zola': '#da3a00',
        'CloudCover IoT, Inc.': '#da3a00',
        'Q4 Roadmap': '#004b51',
        'x (y) z': '#004c1a',
        'Ünïcödé Nämé': '#32105c',
        '한글 이름': '#5d005d',
        'Team 42': '#0075da',
        '123': '#5d005d',
      };
      for (final entry in samples.entries) {
        expect(
          AdoTiles.serviceColor(entry.key),
          c(entry.value),
          reason: entry.key,
        );
      }
    });

    test('initials follow the service rules', () {
      const samples = {
        'DevOps Mobile App': 'DA',
        'CloudCover 2.0': 'C',
        'Product': 'P',
        'Special Projects and AI': 'SA',
        'puremedia': 'P',
        'Boardhop Team': 'BT',
        'Émile Zola': 'ÉZ',
        'CloudCover IoT, Inc.': 'CI',
        'Q4 Roadmap': 'QR',
        '42 Team': 'T',
        'a-b c': 'AC',
        'john.doe': 'J',
        'x (y) z': 'X',
        'x (y)': 'X',
        '(y) x z': 'XZ',
        'x [y] z': 'XZ',
        'x y (z)': 'XY',
        'Dr. Jane Q. Public': 'DP',
        'jane_doe': 'J',
        'x/y z': 'XZ',
        'x & y': 'XY',
        'Jane Doe (Contractor)': 'JD',
        'R2D2 Bot': 'RB',
        'x  y': 'XY',
        ' lead space': 'LS',
        'ab': 'A',
        'x y-z w': 'XW',
        'ÀB CD': 'ÀC',
        'e2e tests': 'ET',
        '한글 이름': '한이',
        'A B C D': 'AD',
        '': '',
        '42': '',
      };
      for (final entry in samples.entries) {
        expect(
          AdoTiles.serviceInitials(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });
  });

  group('coin tiles (azure-devops-ui)', () {
    test('color', () {
      const samples = {
        'puremedia': '#038387',
        'kammcs': '#986f0b',
        'CloudCover 2.0': '#0b6a0b',
        'DevOps Mobile App': '#0078d4',
        'Product': '#d13438',
        'Special Projects and AI': '#7a7574',
        'Kelly Kamm': '#881798',
        'a': '#d13438',
        '': '#4f6bed',
      };
      for (final entry in samples.entries) {
        expect(
          AdoTiles.coinColor(entry.key),
          c(entry.value),
          reason: entry.key,
        );
      }
    });

    test('initials keep digits and skip words that start with symbols', () {
      expect(AdoTiles.coinInitials('puremedia'), 'P');
      expect(AdoTiles.coinInitials('CloudCover 2.0'), 'C2');
      expect(AdoTiles.coinInitials('Special Projects and AI'), 'SA');
      expect(AdoTiles.coinInitials('x (y) z'), 'XZ');
      expect(AdoTiles.coinInitials('  a  '), 'A');
      expect(AdoTiles.coinInitials(''), '');
    });
  });

  group('Project tile source', () {
    test('is the default team avatar, pictures only', () {
      final p = Project.fromJson({
        'id': 'p1',
        'name': 'DevOps Mobile App',
        'defaultTeam': {'id': 'team-1', 'name': 'DevOps Mobile App Team'},
      });
      expect(p.defaultTeamId, 'team-1');
      expect(p.tileSource('puremedia'), isNull, reason: 'no descriptor yet');
      final source = p
          .withDefaultTeam(descriptor: 'vssgp.abc')
          .tileSource('puremedia')!;
      expect(source.isGraph, isTrue);
      expect(source.descriptor, 'vssgp.abc');
      expect(source.picturesOnly, isTrue);
      expect(source.key, 'graph:puremedia:vssgp.abc:large:pictures');
      expect(
        AvatarSource.graph(org: 'o', descriptor: 'd').key,
        'graph:o:d:medium',
      );
      expect(
        Project.fromJson({'id': 'p2', 'name': 'X'}).tileSource('puremedia'),
        isNull,
      );
    });
  });
}
