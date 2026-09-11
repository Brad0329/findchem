import 'package:findchem/parser/name_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitName', () {
    test('국문 [영문] 기본형', () {
      final r = splitName('과산화 나트륨 [Sodium peroxide]');
      expect(r.ko, '과산화 나트륨');
      expect(r.en, 'Sodium peroxide');
      expect(r.usedException, isFalse);
    });

    test('국문 쪽 대괄호는 경계가 아니다', () {
      final r = splitName('벤조[d]이소티아졸-3(2H)-온 [1,2-Benzisothiazol-3(2H)-one]');
      expect(r.ko, '벤조[d]이소티아졸-3(2H)-온');
      expect(r.en, '1,2-Benzisothiazol-3(2H)-one');
    });

    test('영문 앞에 공백이 없어도 나뉜다(별표3 형식)', () {
      final r = splitName('포름산(폼산)[Formic acid]');
      expect(r.ko, '포름산(폼산)');
      expect(r.en, 'Formic acid');
    });

    test('원문 괄호 짝이 틀려도(별표2 341) 한글 없는 첫 [ 로 나뉜다', () {
      const name = '이염화 1-[2-[에틸[4-[4-[4-[에틸(2-피리디노에틸)아미노]-2-메틸페닐아조]벤조일아미노]페닐아조]-3-메틸페닐]아미노]에틸]피리디늄 '
          '[1-[2-[Ethyl[4-[4-[4-[ethyl(2-pyridinoethyl)amino]-2-methylphenylazo]benzoylamino]phenylazo]-3-methylphenyl]amino]ethyl]pyridinium dichloride]';
      final r = splitName(name);
      expect(r.ko, startsWith('이염화 1-[2-[에틸'));
      expect(r.ko, endsWith('피리디늄'));
      expect(r.en, startsWith('1-[2-[Ethyl[4-'));
      expect(r.en, endsWith('pyridinium dichloride'));
    });

    test('예외 목록(1429 `]]`)은 원문 이름 전체를 키로 적용된다', () {
      final r = splitName('5-데신 [5-Decyne]]');
      expect(r.ko, '5-데신');
      expect(r.en, '5-Decyne');
      expect(r.usedException, isTrue);
      // 이름이 조금이라도 다르면 예외가 아니라 일반 규칙이 적용된다
      expect(splitName('5-데신 [5-Decyne]').usedException, isFalse);
    });

    test('영문 뒤에 국문 단서가 붙으면(별표3 33) 단서를 국문에 이어 붙인다', () {
      final r = splitName('시안화나트륨(사이안화나트륨)[Sodium cyanide]다만, 베를린청(Ferric ferrocyanide)은 제외');
      expect(r.en, 'Sodium cyanide');
      expect(r.ko, '시안화나트륨(사이안화나트륨) 다만, 베를린청(Ferric ferrocyanide)은 제외');
      // 국문 쪽 짧은 대괄호가 아니라 긴 영문 덩어리를 고른다
      final r2 = splitName('벤조[d]이소티아졸 [Benzisothiazole]다만');
      expect(r2.en, 'Benzisothiazole');
      expect(r2.ko, '벤조[d]이소티아졸 다만');
    });

    test('영문이 없으면 국문만(별표3 용액 행)', () {
      final r = splitName('염화수소 용액');
      expect(r.ko, '염화수소 용액');
      expect(r.en, '');
    });
  });
}
