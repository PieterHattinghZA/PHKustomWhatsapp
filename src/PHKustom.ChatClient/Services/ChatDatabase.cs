using Microsoft.Data.Sqlite;
using PHKustom.ChatClient.Models;

namespace PHKustom.ChatClient.Services;

public sealed class ChatDatabase(AppPaths paths)
{
    private string ConnectionString => new SqliteConnectionStringBuilder { DataSource = paths.Database }.ToString();

    public async Task InitializeAsync()
    {
        await using var connection = new SqliteConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS Messages(
              Id TEXT PRIMARY KEY, ChatId TEXT NOT NULL, Timestamp INTEGER NOT NULL,
              IsOutgoing INTEGER NOT NULL, Type TEXT NOT NULL, Text TEXT, Caption TEXT,
              DownloadUrl TEXT, FileName TEXT, MimeType TEXT);
            CREATE INDEX IF NOT EXISTS IX_Messages_ChatId_Timestamp ON Messages(ChatId, Timestamp);
            """;
        await command.ExecuteNonQueryAsync();
    }

    public async Task UpsertMessagesAsync(IEnumerable<ChatMessage> messages, CancellationToken token)
    {
        await using var connection = new SqliteConnection(ConnectionString);
        await connection.OpenAsync(token);
        await using var transaction = (SqliteTransaction)await connection.BeginTransactionAsync(token);
        foreach (var item in messages)
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO Messages VALUES($id,$chat,$timestamp,$outgoing,$type,$text,$caption,$url,$file,$mime)
                ON CONFLICT(Id) DO UPDATE SET Text=$text, Caption=$caption, DownloadUrl=$url, FileName=$file, MimeType=$mime;
                """;
            command.Parameters.AddWithValue("$id", item.Id);
            command.Parameters.AddWithValue("$chat", item.ChatId);
            command.Parameters.AddWithValue("$timestamp", item.Timestamp);
            command.Parameters.AddWithValue("$outgoing", item.IsOutgoing ? 1 : 0);
            command.Parameters.AddWithValue("$type", item.Type);
            command.Parameters.AddWithValue("$text", (object?)item.Text ?? DBNull.Value);
            command.Parameters.AddWithValue("$caption", (object?)item.Caption ?? DBNull.Value);
            command.Parameters.AddWithValue("$url", (object?)item.DownloadUrl ?? DBNull.Value);
            command.Parameters.AddWithValue("$file", (object?)item.FileName ?? DBNull.Value);
            command.Parameters.AddWithValue("$mime", (object?)item.MimeType ?? DBNull.Value);
            await command.ExecuteNonQueryAsync(token);
        }
        await transaction.CommitAsync(token);
    }
}
