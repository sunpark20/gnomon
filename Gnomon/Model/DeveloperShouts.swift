//
//  DeveloperShouts.swift
//  Gnomon
//
//  "개발자의 외침" — 기본 위트 문구와 10초 간격으로 교대로 표시되는
//  개발자 직접 채우는 콘텐츠 (홈페이지 링크, 후원 QR 등).
//  빈 리스트여도 동작한다. 비어 있으면 매 턴 위트 문구로 폴백.
//

import Foundation

public enum DeveloperShout: Sendable, Hashable {
    case text(String)
    case link(title: String, url: URL)
    /// `payload`는 QR 코드로 인코딩될 문자열 (URL, 결제 딥링크 등).
    case qrCode(title: String, payload: String)
}

public enum DeveloperShouts {
    /// 여기에 외침들을 채우세요. 예:
    ///   .text("개발 중입니다. 피드백 환영!"),
    ///   .link(title: "홈페이지", url: URL(string: "https://example.com")!),
    ///   .qrCode(title: "후원해주세요", payload: "supertoss://..."),
    public static let all: [DeveloperShout] = []

    /// 후원 QR은 국내 결제 수단이라 한국어 환경에서만 노출한다.
    public static func visible(for locale: Locale = .current) -> [DeveloperShout] {
        let isKorean = locale.language.languageCode?.identifier == "ko"
        return all.filter { shout in
            switch shout {
            case .text, .link: true
            case .qrCode: isKorean
            }
        }
    }
}

/// 메시지 영역에 표시될 한 턴의 콘텐츠. 기본 위트 또는 개발자 외침.
public enum DisplayMessage: Sendable, Hashable {
    case witty(String)
    case shout(DeveloperShout)
}
