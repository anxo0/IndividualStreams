/*
 * IndividualStreams, un plugin para Vencord
 * Copyright (c) 2026 anxo0
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { NavContextMenuPatchCallback } from "@api/ContextMenu";
import ErrorBoundary from "@components/ErrorBoundary";
import definePlugin from "@utils/types";
import { findByPropsLazy, findExportedComponentLazy, findStoreLazy } from "@webpack";
import { ApplicationStreamingStore, FluxDispatcher, MediaEngineStore, Menu, PopoutWindowStore, React, showToast, UserStore, useStateFromStores } from "@webpack/common";

const ChannelRTCStore = findStoreLazy("ChannelRTCStore");
const AudioActions = findByPropsLazy("toggleLocalMute", "setLocalVolume");
const WindowLaunchIconModule = findByPropsLazy("WindowLaunchIcon");
const FullscreenEnterIcon = findExportedComponentLazy("FullscreenEnterIcon");
const VoiceNormalIcon = findExportedComponentLazy("VoiceNormalIcon");
const VoiceLowIcon = findExportedComponentLazy("VoiceLowIcon");
const VoiceXIcon = findExportedComponentLazy("VoiceXIcon");

const PARTICIPANT_TYPE_STREAM = 0;

// El mismo icono de "Abrir en ventana" de Discord, con un 1 dentro
function IndividualIcon(props: any) {
    const icon = WindowLaunchIconModule.WindowLaunchIcon(props);
    const [firstPath] = React.Children.toArray(icon.props.children) as React.ReactElement<any>[];

    return React.cloneElement(icon, undefined, icon.props.children,
        <path
            fill={firstPath.props.fill}
            className={firstPath.props.className}
            d="M12 9.5V18h-2v-5.9l-1.6 1-1-1.7 2.9-1.9z"
        />
    );
}

function openParticipant(channelId: string, participantId: string) {
    // La saca de la cuadrícula principal; Discord la devuelve sola al cerrar la ventana
    FluxDispatcher.dispatch({ type: "CHANNEL_RTC_POPOUT_PARTICIPANT", channelId, participantId });

    // Discord abre una ventana distinta por cada participante
    FluxDispatcher.dispatch({ type: "CALL_TILE_POPOUT_WINDOW_OPEN", channelId, participantId });
}

function openIndividual(ownerId: string) {
    const stream = ApplicationStreamingStore.getActiveStreamForUser(ownerId)
        ?? ApplicationStreamingStore.getAllActiveStreams().find(s => s.ownerId === ownerId);

    const participant = stream && ChannelRTCStore.getStreamParticipants(stream.channelId)
        .find(p => p.stream?.ownerId === ownerId);

    if (!stream || !participant) {
        showToast({ text: "Primero tienes que estar viendo esa transmisión", variant: "critical" });
        return;
    }

    openParticipant(stream.channelId, participant.id);
}

// Lleva la ventana individual al punto de la pantalla donde se soltó la transmisión
function moveWindowTo(channelId: string, participantId: string, screenX: number, screenY: number) {
    const key = `DISCORD_CALL_TILE_POPOUT_${channelId}_${participantId}`;
    const startedAt = Date.now();

    const tryMove = () => {
        const win = PopoutWindowStore.getWindow(key);
        if (win && win.outerWidth > 0) {
            try { win.moveTo(Math.round(screenX - win.outerWidth / 2), Math.round(screenY - 16)); } catch { }
            return;
        }
        if (Date.now() - startedAt < 3000) setTimeout(tryMove, 50);
    };
    tryMove();
}

const DRAG_THRESHOLD = 8;

// Arrastrar una transmisión fuera de su recuadro la abre en ventana individual donde se suelte
function startTileDrag(e: React.MouseEvent, participant: any) {
    const channelId = participant.stream?.channelId;
    const tile = e.currentTarget as HTMLElement;
    const doc = tile.ownerDocument;
    // Solo en la cuadrícula de la llamada, no dentro de las ventanas que ya están fuera
    if (e.button !== 0 || !channelId || doc !== document) return;

    const startX = e.clientX, startY = e.clientY;
    let ghost: HTMLDivElement | null = null;

    const isOutsideTile = (ev: MouseEvent) => {
        const r = tile.getBoundingClientRect();
        return ev.clientX < r.left || ev.clientX > r.right || ev.clientY < r.top || ev.clientY > r.bottom;
    };

    const onMove = (ev: MouseEvent) => {
        if (!ghost) {
            if (Math.hypot(ev.clientX - startX, ev.clientY - startY) < DRAG_THRESHOLD) return;
            ghost = doc.createElement("div");
            ghost.textContent = "Suelta para abrir individual";
            Object.assign(ghost.style, {
                position: "fixed", zIndex: "10000", pointerEvents: "none", padding: "8px 12px", borderRadius: "8px",
                background: "rgba(17, 18, 20, 0.92)", color: "#fff", font: "600 14px var(--font-primary, sans-serif)",
                boxShadow: "0 8px 24px rgba(0, 0, 0, 0.4)", whiteSpace: "nowrap", transition: "opacity 120ms"
            });
            doc.body.appendChild(ghost);
            doc.documentElement.style.cursor = "grabbing";
        }
        ev.preventDefault();
        ghost.style.left = `${ev.clientX + 14}px`;
        ghost.style.top = `${ev.clientY + 14}px`;
        // Dentro de su propio recuadro no se abre nada al soltar
        ghost.style.opacity = isOutsideTile(ev) ? "1" : "0.45";
    };

    const onUp = (ev: MouseEvent) => {
        doc.removeEventListener("mousemove", onMove, true);
        doc.removeEventListener("mouseup", onUp, true);
        if (!ghost) return;

        ghost.remove();
        doc.documentElement.style.cursor = "";
        if (!isOutsideTile(ev)) return;

        // El clic que sigue al soltar no debe cambiar la transmisión enfocada
        const swallowClick = (c: MouseEvent) => { c.stopPropagation(); c.preventDefault(); };
        doc.addEventListener("click", swallowClick, { capture: true, once: true });
        setTimeout(() => doc.removeEventListener("click", swallowClick, true), 0);

        openParticipant(channelId, participant.id);
        moveWindowTo(channelId, participant.id, ev.screenX, ev.screenY);
    };

    doc.addEventListener("mousemove", onMove, true);
    doc.addEventListener("mouseup", onUp, true);
}

function toggleFullscreen(e: React.MouseEvent) {
    const doc = (e.currentTarget as HTMLElement).ownerDocument;
    if (doc.fullscreenElement) doc.exitFullscreen();
    else doc.getElementById("app-mount")?.requestFullscreen();
}

// Reutiliza el botón de "Abrir en ventana" de Discord cambiándole solo el icono y el texto
const BarButton = ErrorBoundary.wrap(({ PopoutButton, channelId, participantId, ...rest }: any) => (
    <PopoutButton
        {...rest}
        popoutOpen={false}
        onOpenPopout={() => openParticipant(channelId, participantId)}
        onClosePopout={() => { }}
        label="Abrir individual"
        iconComponent={IndividualIcon}
    />
), { noop: true });

// Discord guarda el volumen como amplitud y lo muestra en una escala perceptiva (0 a 200 en escritorio)
const MAX_VOLUME = IS_DISCORD_DESKTOP ? 200 : 100;
const toSlider = (v: number) => v === 0 ? 0 : (v < 100 ? Math.pow(v / 100, 1 / 2.8) : 20 * Math.log10(v / 100) / 6 + 1) * 100;
const toAmplitude = (v: number) => v === 0 ? 0 : (v < 100 ? Math.pow(v / 100, 2.8) : Math.pow(10, (v / 100 - 1) * 6 / 20)) * 100;

// Deslizador vertical con el aspecto del de Discord: barra fina, relleno azul desde abajo y bolita
function VolumeSlider({ value, onChange }: { value: number; onChange(value: number): void; }) {
    const trackRef = React.useRef<HTMLDivElement>(null);
    const percent = (value / MAX_VOLUME) * 100;

    const update = (clientY: number) => {
        const rect = trackRef.current?.getBoundingClientRect();
        if (!rect) return;
        const ratio = Math.max(0, Math.min(1, (rect.bottom - clientY) / rect.height));
        onChange(Math.round(ratio * MAX_VOLUME));
    };

    return (
        <div
            role="slider"
            aria-label="Volumen de la transmisión"
            aria-valuemin={0}
            aria-valuemax={MAX_VOLUME}
            aria-valuenow={value}
            aria-valuetext={`${value}%`}
            tabIndex={0}
            onPointerDown={e => { e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId); update(e.clientY); }}
            onPointerMove={e => { if (e.currentTarget.hasPointerCapture(e.pointerId)) update(e.clientY); }}
            onKeyDown={e => {
                const step = e.key === "ArrowUp" || e.key === "ArrowRight" ? 5 : e.key === "ArrowDown" || e.key === "ArrowLeft" ? -5 : 0;
                if (step) { e.preventDefault(); onChange(Math.max(0, Math.min(MAX_VOLUME, value + step))); }
            }}
            style={{
                display: "flex", justifyContent: "center", width: 24, padding: "12px 0",
                borderRadius: 12, background: "rgba(0, 0, 0, 0.6)", cursor: "pointer", outline: "none", touchAction: "none"
            }}
        >
            <div ref={trackRef} style={{ position: "relative", width: 4, height: 96, borderRadius: 2, background: "#4e5058" }}>
                <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: `${percent}%`, borderRadius: 2, background: "#5865f2" }} />
                <div style={{
                    position: "absolute", left: "50%", bottom: `${percent}%`, width: 10, height: 10,
                    borderRadius: "50%", background: "#5865f2", transform: "translate(-50%, 50%)"
                }} />
            </div>
        </div>
    );
}

const PopoutVolume = ErrorBoundary.wrap(({ userId, idle, TileButton, hideWhenInactive = false }: { userId: string; idle: boolean; TileButton: any; hideWhenInactive?: boolean; }) => {
    const [open, setOpen] = React.useState(false);
    const closeTimer = React.useRef<any>(null);

    const { volume, muted } = useStateFromStores([MediaEngineStore], () => ({
        volume: toSlider((MediaEngineStore as any).getLocalVolume(userId, "stream")),
        muted: (MediaEngineStore as any).isLocalMute(userId, "stream") as boolean
    }));

    const shown = muted ? 0 : Math.round(volume);
    const Icon = shown === 0 ? VoiceXIcon : shown < MAX_VOLUME / 2 ? VoiceLowIcon : VoiceNormalIcon;

    const setVolume = (value: number) => {
        value = Math.max(0, Math.min(MAX_VOLUME, value));
        if (value > 0 && muted) AudioActions.toggleLocalMute(userId, "stream");
        AudioActions.setLocalVolume(userId, toAmplitude(value), "stream");
    };

    const show = () => { clearTimeout(closeTimer.current); setOpen(true); };
    const hide = () => { clearTimeout(closeTimer.current); closeTimer.current = setTimeout(() => setOpen(false), 200); };
    React.useEffect(() => () => clearTimeout(closeTimer.current), []);

    return (
        <div
            style={{ position: "relative", display: "flex", pointerEvents: "auto" }}
            onMouseEnter={show}
            onMouseLeave={hide}
            onClick={e => e.stopPropagation()}
            onDoubleClick={e => e.stopPropagation()}
            // En la cuadrícula, que tocar el volumen no empiece a arrastrar la transmisión
            onMouseDown={e => e.stopPropagation()}
            onWheel={e => setVolume(shown + (e.deltaY < 0 ? 5 : -5))}
        >
            {open && !idle && (
                // El hueco de abajo (paddingBottom) mantiene el deslizador abierto al subir el ratón desde el botón
                // pointerEvents: la barra de controles de Discord desactiva el ratón fuera de sus botones
                <div style={{ position: "absolute", bottom: "100%", left: "50%", transform: "translateX(-50%)", paddingBottom: 6, pointerEvents: "auto", zIndex: 1 }}>
                    <VolumeSlider value={shown} onChange={setVolume} />
                </div>
            )}
            <TileButton
                icon={Icon}
                // Sin aviso mientras el deslizador está abierto: se pondría encima y lo taparía
                tooltipText={open ? null : muted ? "Activar sonido" : "Silenciar"}
                hideWhenInactive={hideWhenInactive && !open}
                idle={idle}
                onClick={(e: React.MouseEvent<HTMLElement>) => {
                    // Si el botón se queda con el foco, Discord deja su aviso fijo hasta hacer clic en otro sitio
                    e.currentTarget?.blur?.();
                    AudioActions.toggleLocalMute(userId, "stream");
                }}
            />
        </div>
    );
}, { noop: true });

function addItem(children: Array<React.ReactNode>, ownerId: string) {
    children.push(
        <Menu.MenuSeparator />,
        <Menu.MenuItem
            id="vc-open-individual-stream"
            label="Abrir individual"
            action={() => openIndividual(ownerId)}
        />
    );
}

const streamContextPatch: NavContextMenuPatchCallback = (children, { stream }) => {
    if (stream?.ownerId) addItem(children, stream.ownerId);
};

const userContextPatch: NavContextMenuPatchCallback = (children, { user }) => {
    if (user && ApplicationStreamingStore.getAnyStreamForUser(user.id)) addItem(children, user.id);
};

export default definePlugin({
    name: "IndividualStreams",
    description: "Abre cada transmisión en su propia ventana para repartirlas entre varias pantallas",
    authors: [{ name: "anxo0", id: 423152530235850753n }],
    enabledByDefault: true,

    patches: [
        {
            // Barra de controles de la llamada: botón junto al de "Abrir en ventana"
            find: "renderBottomRight=()=>",
            replacement: {
                match: /\i\?\(0,\i\.jsx\)\((\i\.\i),\{themeable:(\i),popoutOpen:this\.popoutOpen,className:(\i\.\i),/,
                replace: "$self.renderBarButton(this.props,{PopoutButton:$1,themeable:$2,className:$3}),$&"
            }
        },
        {
            // Ventana individual: volumen y pantalla completa junto a los botones que ya trae
            find: '"stay-on-top"',
            replacement: [
                {
                    match: /(\i)\.push\(\(0,\i\.jsx\)\(\i,\{channelId:(\i)\.id,participantId:(\i),hideWhenInactive:!1,idle:(\i)\},"stay-on-top"\)\),\i\.push\(\(0,\i\.jsx\)\((\i),\{/,
                    replace: "$self.pushPopoutControls($1,{channelId:$2.id,participantId:$3,idle:$4,TileButton:$5}),$&"
                },
                {
                    // Recuadro de la cuadrícula: arrastrar una transmisión fuera la abre en ventana individual
                    match: /(onContextMenu:\i=>\i\(\i,(\i)\.type===\i\.\i\.STREAM\),onClick:\i,onMouseDown:)(\i),/,
                    replace: "$1$self.tileMouseDown($2,$3),"
                },
                {
                    // Recuadro de la cuadrícula: el botón de silenciar de Discord pasa a ser nuestro volumen con deslizador
                    match: /(participantUserId:(\i),[\s\S]{0,4000}?)(\i)&&(\i)\.push\(\(0,\i\.jsx\)\((\i),\{onClick:\i,tooltipText:[^}]{0,200}?hideWhenInactive:([^,]+),idle:(\i)\},"mute"\)\)/,
                    replace: "$1$3&&$4.push($self.renderTileVolume({userId:$2,TileButton:$5,hideWhenInactive:$6,idle:$7}))"
                }
            ]
        }
    ],

    renderBarButton(props: any, buttonProps: any) {
        try {
            const { channel, selectedParticipant } = props;
            if (!channel || selectedParticipant?.type !== PARTICIPANT_TYPE_STREAM) return null;

            return <BarButton key="vc-individual-stream" {...buttonProps} channelId={channel.id} participantId={selectedParticipant.id} />;
        } catch {
            return null;
        }
    },

    renderTileVolume({ userId, TileButton, hideWhenInactive, idle }: any) {
        return <PopoutVolume key="mute" userId={userId} TileButton={TileButton} hideWhenInactive={hideWhenInactive} idle={idle} />;
    },

    tileMouseDown(participant: any, original?: (e: React.MouseEvent) => void) {
        return (e: React.MouseEvent) => {
            original?.(e);
            try {
                if (participant?.type === PARTICIPANT_TYPE_STREAM) startTileDrag(e, participant);
            } catch { }
        };
    },

    pushPopoutControls(buttons: React.ReactNode[], { channelId, participantId, idle, TileButton }: any) {
        try {
            // Volumen solo para transmisiones ajenas: la tuya no se oye en tu propio Discord
            const participant = ChannelRTCStore.getParticipant(channelId, participantId);
            const userId = participant?.user?.id;
            if (participant?.type === PARTICIPANT_TYPE_STREAM && userId && userId !== UserStore.getCurrentUser()?.id)
                buttons.push(<PopoutVolume key="vc-individual-volume" userId={userId} idle={idle} TileButton={TileButton} />);

            buttons.push(
                <TileButton
                    key="vc-individual-fullscreen"
                    icon={FullscreenEnterIcon}
                    tooltipText="Pantalla completa"
                    hideWhenInactive={false}
                    idle={idle}
                    onClick={toggleFullscreen}
                />
            );
        } catch { }
    },

    contextMenus: {
        "stream-context": streamContextPatch,
        "user-context": userContextPatch
    }
});
