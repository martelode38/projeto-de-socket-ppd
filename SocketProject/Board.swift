//
//  Board.swift
//  SocketProject
//
//  Created by OpenAI.
//

import Foundation

struct BoardPosition: Identifiable, Hashable, Codable {
    let row: Int
    let column: Int

    var id: String {
        "\(row)-\(column)"
    }
}

enum PieceOwner: String, Codable {
    case white
    case black
}

struct Piece: Identifiable, Hashable, Codable {
    let id: UUID
    let owner: PieceOwner
    let position: BoardPosition

    init(owner: PieceOwner, position: BoardPosition) {
        self.id = UUID()
        self.owner = owner
        self.position = position
    }
}

struct Board {
    static let rows = 5
    static let columns = 9

    let positions: [BoardPosition]
    var pieces: [BoardPosition: Piece]

    init(positions: [BoardPosition], pieces: [BoardPosition: Piece]) {
        self.positions = positions
        self.pieces = pieces
    }

    static func initial() -> Board {
        var positions: [BoardPosition] = []
        var pieces: [BoardPosition: Piece] = [:]

        for row in 0..<rows {
            for column in 0..<columns {
                let position = BoardPosition(row: row, column: column)
                positions.append(position)

                switch row {
                case 0, 1:
                    pieces[position] = Piece(owner: .white, position: position)
                case 2:
                    if column != 4 {
                        let owner: PieceOwner = column.isMultiple(of: 2) ? .white : .black
                        pieces[position] = Piece(owner: owner, position: position)
                    }
                case 3, 4:
                    pieces[position] = Piece(owner: .black, position: position)
                default:
                    break
                }
            }
        }

        return Board(positions: positions, pieces: pieces)
    }

    func piece(at position: BoardPosition) -> Piece? {
        pieces[position]
    }

    func isEmpty(at position: BoardPosition) -> Bool {
        pieces[position] == nil
    }

    mutating func movePiece(from source: BoardPosition, to destination: BoardPosition) {
        guard let piece = pieces[source] else { return }
        guard pieces[destination] == nil else { return }

        pieces[source] = nil
        pieces[destination] = Piece(owner: piece.owner, position: destination)
    }
}
