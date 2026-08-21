'use client';

import { useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';

import { useSession } from '@/components/auth/session-provider';
import { crmFetch } from '@/lib/backend/client';
import type { ManagedEmployee } from '@/lib/f2/types';
import type {
  InboxConversation,
  InboxConversationList,
  InboxMessage,
  InboxMessageList,
  InboxQuickReply,
} from '@/lib/f3/types';

type Filter = 'ALL' | 'OPEN' | 'CLOSED';

type TemplateForm = {
  templateName: string;
  languageCode: string;
};

const emptyTemplate: TemplateForm = { templateName: '', languageCode: 'pt_BR' };

function displayName(conversation: InboxConversation): string {
  return conversation.contact.profileName?.trim() || conversation.contact.waId;
}

function formatTime(value: string | null): string {
  if (!value) return '';
  return new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' }).format(new Date(value));
}

function formatDateTime(value: string | null): string {
  if (!value) return 'Sem registro';
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
}

function messagePreview(message: InboxMessage | null): string {
  if (!message) return 'Sem mensagens';
  if (message.textBody) return message.textBody;
  return message.type === 'TEMPLATE' ? 'Template enviado' : `Mensagem ${message.type.toLowerCase()}`;
}

function messageLabel(message: InboxMessage): string {
  if (message.textBody) return message.textBody;
  if (message.type === 'TEMPLATE') return 'Template WhatsApp';
  return `Conteudo ${message.type.toLowerCase()}`;
}

export function InboxWorkspace() {
  const { user } = useSession();
  const isAdmin = Boolean(user?.roles.includes('ADMIN'));
  const [conversations, setConversations] = useState<readonly InboxConversation[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<readonly InboxMessage[]>([]);
  const [quickReplies, setQuickReplies] = useState<readonly InboxQuickReply[]>([]);
  const [employees, setEmployees] = useState<readonly ManagedEmployee[]>([]);
  const [filter, setFilter] = useState<Filter>('OPEN');
  const [search, setSearch] = useState('');
  const [draft, setDraft] = useState('');
  const [loadingList, setLoadingList] = useState(true);
  const [loadingChat, setLoadingChat] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [quickOpen, setQuickOpen] = useState(false);
  const [templateOpen, setTemplateOpen] = useState(false);
  const [templateForm, setTemplateForm] = useState<TemplateForm>(emptyTemplate);

  const selected = conversations.find((item) => item.id === selectedId) ?? null;

  async function loadConversations(preferredId?: string | null) {
    setLoadingList(true);
    setError(null);
    try {
      const params = new URLSearchParams({ limit: '100' });
      if (filter !== 'ALL') params.set('status', filter);
      if (search.trim()) params.set('search', search.trim());
      const data = await crmFetch<InboxConversationList>(`/api/inbox/conversations?${params.toString()}`);
      setConversations(data.items);
      const candidate = preferredId && data.items.some((item) => item.id === preferredId)
        ? preferredId
        : data.items[0]?.id ?? null;
      setSelectedId(candidate);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel carregar o Inbox.');
    } finally {
      setLoadingList(false);
    }
  }

  async function loadConversation(conversationId: string) {
    setLoadingChat(true);
    setError(null);
    try {
      const [conversation, messageData] = await Promise.all([
        crmFetch<InboxConversation>(`/api/inbox/conversations/${conversationId}`),
        crmFetch<InboxMessageList>(`/api/inbox/conversations/${conversationId}/messages?limit=100`),
      ]);
      setMessages([...messageData.items].reverse());
      setConversations((current) => current.map((item) => item.id === conversation.id ? conversation : item));
      if (conversation.unreadCount > 0) {
        const read = await crmFetch<InboxConversation>(`/api/inbox/conversations/${conversationId}/read`, { method: 'POST' });
        setConversations((current) => current.map((item) => item.id === read.id ? read : item));
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel abrir a conversa.');
    } finally {
      setLoadingChat(false);
    }
  }

  useEffect(() => {
    void loadConversations();
  }, [filter]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadConversations(selectedId), 300);
    return () => window.clearTimeout(timer);
  }, [search]);

  useEffect(() => {
    if (selectedId) void loadConversation(selectedId);
    else setMessages([]);
  }, [selectedId]);

  useEffect(() => {
    async function loadAuxiliary() {
      try {
        const replies = await crmFetch<readonly InboxQuickReply[]>('/api/inbox/quick-replies');
        setQuickReplies(replies);
        if (isAdmin) {
          const employeeData = await crmFetch<readonly ManagedEmployee[]>('/api/management/employees');
          setEmployees(employeeData.filter((employee) => !employee.roles.includes('ADMIN')));
        }
      } catch {
        // The inbox remains usable even if auxiliary controls fail.
      }
    }
    if (user) void loadAuxiliary();
  }, [isAdmin, user]);

  const counts = useMemo(() => ({
    all: conversations.length,
    unread: conversations.filter((item) => item.unreadCount > 0).length,
  }), [conversations]);

  async function sendText(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selected || !draft.trim() || !selected.isCustomerServiceWindowOpen) return;
    setSending(true);
    setError(null);
    try {
      const message = await crmFetch<InboxMessage>(`/api/inbox/conversations/${selected.id}/messages`, {
        method: 'POST',
        body: JSON.stringify({ clientMessageId: crypto.randomUUID(), type: 'TEXT', text: draft.trim() }),
      });
      setMessages((current) => [...current, message]);
      setDraft('');
      await loadConversations(selected.id);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel enviar a mensagem.');
    } finally {
      setSending(false);
    }
  }

  async function sendTemplate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selected) return;
    setSending(true);
    setError(null);
    try {
      const message = await crmFetch<InboxMessage>(`/api/inbox/conversations/${selected.id}/messages`, {
        method: 'POST',
        body: JSON.stringify({
          clientMessageId: crypto.randomUUID(),
          type: 'TEMPLATE',
          templateName: templateForm.templateName.trim(),
          languageCode: templateForm.languageCode.trim(),
        }),
      });
      setMessages((current) => [...current, message]);
      setTemplateOpen(false);
      setTemplateForm(emptyTemplate);
      await loadConversations(selected.id);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel enviar o template.');
    } finally {
      setSending(false);
    }
  }

  async function updateConversation(body: Record<string, unknown>) {
    if (!selected) return;
    setError(null);
    try {
      const updated = await crmFetch<InboxConversation>(`/api/inbox/conversations/${selected.id}`, {
        method: 'PATCH',
        body: JSON.stringify(body),
      });
      setConversations((current) => current.map((item) => item.id === updated.id ? updated : item));
      if ((body.status === 'CLOSED' || body.status === 'ARCHIVED') && filter === 'OPEN') {
        await loadConversations();
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Nao foi possivel atualizar a conversa.');
    }
  }

  return (
    <div className="f3-page">
      <section className="f3-heading">
        <div>
          <span className="f3-kicker">WHATSAPP CLOUD API</span>
          <h1>Inbox</h1>
          <p>Atenda conversas no numero correto, respeitando atribuicao e janela oficial de atendimento.</p>
        </div>
        <div className="f3-heading-stats"><span><b>{counts.all}</b> visiveis</span><span><b>{counts.unread}</b> nao lidas</span></div>
      </section>

      {error ? <div className="f3-alert">{error}</div> : null}

      <section className="f3-inbox-shell">
        <aside className="f3-conversation-panel">
          <div className="f3-list-header">
            <label className="f3-search"><span>⌕</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar contato ou numero" /></label>
            <div className="f3-tabs">
              {(['OPEN', 'ALL', 'CLOSED'] as const).map((value) => <button key={value} type="button" className={filter === value ? 'active' : ''} onClick={() => setFilter(value)}>{value === 'OPEN' ? 'Abertas' : value === 'CLOSED' ? 'Fechadas' : 'Todas'}</button>)}
            </div>
          </div>
          <div className="f3-conversation-list">
            {loadingList ? <div className="f3-empty">Carregando conversas...</div> : null}
            {!loadingList && conversations.length === 0 ? <div className="f3-empty">Nenhuma conversa encontrada.</div> : null}
            {conversations.map((conversation) => (
              <button type="button" key={conversation.id} onClick={() => setSelectedId(conversation.id)} className={`f3-conversation${selectedId === conversation.id ? ' active' : ''}`}>
                <span className="f3-contact-avatar">{displayName(conversation).charAt(0).toUpperCase()}</span>
                <span className="f3-conversation-copy"><strong>{displayName(conversation)}</strong><small>{messagePreview(conversation.lastMessage)}</small><em>{conversation.whatsAppNumber.displayName}</em></span>
                <span className="f3-conversation-meta"><time>{formatTime(conversation.lastMessageAt)}</time>{conversation.unreadCount > 0 ? <b>{conversation.unreadCount}</b> : null}</span>
              </button>
            ))}
          </div>
        </aside>

        <main className="f3-chat-panel">
          {!selected ? <div className="f3-empty-chat"><strong>Selecione uma conversa</strong><span>As mensagens aparecerao aqui.</span></div> : (
            <>
              <header className="f3-chat-header">
                <div className="f3-chat-contact"><span className="f3-contact-avatar">{displayName(selected).charAt(0).toUpperCase()}</span><div><strong>{displayName(selected)}</strong><span>{selected.contact.waId} · via {selected.whatsAppNumber.displayName}</span></div></div>
                <div className="f3-chat-actions">
                  <span className={`f3-window ${selected.isCustomerServiceWindowOpen ? 'open' : 'closed'}`}>{selected.isCustomerServiceWindowOpen ? `24h ate ${formatDateTime(selected.customerServiceWindowExpiresAt)}` : 'Janela 24h fechada'}</span>
                  <button type="button" onClick={() => void updateConversation({ status: selected.status === 'OPEN' ? 'CLOSED' : 'OPEN' })}>{selected.status === 'OPEN' ? 'Encerrar' : 'Reabrir'}</button>
                </div>
              </header>

              <div className="f3-chat-body">
                {loadingChat ? <div className="f3-empty">Carregando mensagens...</div> : null}
                {!loadingChat && messages.length === 0 ? <div className="f3-empty">Ainda nao ha mensagens nesta conversa.</div> : null}
                {messages.map((message) => (
                  <article key={message.id} className={`f3-message ${message.direction === 'OUTBOUND' ? 'outbound' : 'inbound'}`}>
                    <div><p>{messageLabel(message)}</p><span>{formatTime(message.providerTimestamp ?? message.createdAt)} · {message.status}</span>{message.errorMessage ? <small>{message.errorMessage}</small> : null}</div>
                  </article>
                ))}
              </div>

              <footer className="f3-composer">
                <div className="f3-composer-tools">
                  <button type="button" onClick={() => setQuickOpen((value) => !value)}>Respostas rapidas</button>
                  <button type="button" onClick={() => setTemplateOpen(true)}>Template</button>
                  {isAdmin ? <select value={selected.assignedEmployee?.employeeId ?? ''} onChange={(event) => void updateConversation({ assignedEmployeeId: event.target.value || null })}><option value="">Sem atribuicao</option>{employees.filter((employee) => employee.status === 'ACTIVE').map((employee) => <option value={employee.id} key={employee.id}>{employee.user.displayName}</option>)}</select> : null}
                </div>
                {quickOpen ? <div className="f3-quick-menu">{quickReplies.length === 0 ? <span>Nenhuma resposta rapida cadastrada.</span> : quickReplies.map((reply) => <button key={reply.id} type="button" onClick={() => { setDraft(reply.body); setQuickOpen(false); }}><strong>/{reply.shortcut}</strong><span>{reply.title}</span></button>)}</div> : null}
                <form onSubmit={sendText} className="f3-compose-form">
                  <textarea value={draft} onChange={(event) => setDraft(event.target.value)} disabled={!selected.isCustomerServiceWindowOpen || sending} placeholder={selected.isCustomerServiceWindowOpen ? 'Digite uma mensagem...' : 'Janela de 24h fechada. Use um template aprovado.'} />
                  <button type="submit" disabled={!draft.trim() || !selected.isCustomerServiceWindowOpen || sending}>{sending ? 'Enviando...' : 'Enviar'}</button>
                </form>
              </footer>
            </>
          )}
        </main>
      </section>

      {templateOpen && selected ? <div className="f3-modal-backdrop"><section className="f3-modal"><div className="f3-modal-header"><div><span className="f3-kicker">TEMPLATE APROVADO</span><h2>Enviar template</h2></div><button type="button" onClick={() => setTemplateOpen(false)}>×</button></div><p>Use exatamente o nome e idioma de um template aprovado na Meta.</p><form onSubmit={sendTemplate}><label><span>Nome do template</span><input required value={templateForm.templateName} onChange={(event) => setTemplateForm((current) => ({ ...current, templateName: event.target.value }))} /></label><label><span>Idioma</span><input required value={templateForm.languageCode} onChange={(event) => setTemplateForm((current) => ({ ...current, languageCode: event.target.value }))} /></label><div className="f3-modal-actions"><button type="button" onClick={() => setTemplateOpen(false)}>Cancelar</button><button type="submit" disabled={sending}>{sending ? 'Enviando...' : 'Enviar template'}</button></div></form></section></div> : null}
    </div>
  );
}
