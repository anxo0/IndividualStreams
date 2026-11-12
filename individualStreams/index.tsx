/*
 * IndividualStreams, un plugin para Vencord
 * Copyright (c) 2026 anxo0
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { NavContextMenuPatchCallback } from "@api/ContextMenu";
import ErrorBoundary from "@components/ErrorBoundary";
import definePlugin from "@utils/types";
import { findComponentByCodeLazy, findStoreLazy } from "@webpack";
import { ApplicationStreamingStore, FluxDispatcher, Menu, PopoutWindowStore, showToast, Tooltip, UserStore, useState } from "@webpack/common";

const ChannelRTCStore = findStoreLazy("ChannelRTCStore");
const VolumeControl = findComponentByCodeLazy("currentVolume:", "sliderClassName:");

const PARTICIPANT_TYPE_STREAM = 0;
const ICON_SIZES: Record<string, number> = { xxs: 12, xs: 16, sm: 18, md: 24, lg: 32 };

function iconSize(size: unknown) {
    return typeof size === "number" ? size : ICON_SIZES[size as string] ?? 20;
}

function IndividualIcon({ size, className }: { size?: unknown; className?: string; }) {
    const px = iconSize(size);
    return (
        <svg className={className} width={px} height={px} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M15 3h6v6h-2V6.4l-6.3 6.3-1.4-1.4L17.6 5H15z" />
            <path d="M5 5h7v2H5v12h12v-7h2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />
            <path d="M8.9 11.6h1.9V18H9v-4.5l-1.3.5v-1.6z" />
        </svg>
    );
}

function FullscreenIcon({ size, className }: { size?: unknown; className?: string; }) {
    const px = iconSize(size);
    return (
        <svg className={className} width={px} height={px} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M4 4h6v2H6v4H4zm10 0h6v6h-2V6h-4zM4 14h2v4h4v2H4zm14 0h2v6h-6v-2h4z" />
        </svg>
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

function toggleFullscreen(e: React.MouseEvent) {
    const doc = (e.currentTarget as HTMLElement).ownerDocument;
    if (doc.fullscreenElement) doc.exitFullscreen();
    else doc.getElementById("app-mount")?.requestFullscreen();
}

const BarButton = ErrorBoundary.wrap(({ channelId, participantId, className }: { channelId: string; participantId: string; className?: string; }) => {
    const [hovered, setHovered] = useState(false);

    return (
        <Tooltip text="Abrir individual">
            {tooltipProps => (
                <button
                    {...tooltipProps}
                    className={className}
                    aria-label="Abrir individual"
                    style={{
                        display: "flex",
                        padding: 4,
                        background: "none",
                        border: "none",
                        cursor: "pointer",
                        color: "#fff",
                        opacity: hovered ? 1 : 0.8
                    }}
                    onMouseEnter={() => { tooltipProps.onMouseEnter(); setHovered(true); }}
                    onMouseLeave={() => { tooltipProps.onMouseLeave(); setHovered(false); }}
                    onClick={() => openParticipant(channelId, participantId)}
                >
                    <IndividualIcon size={24} />
                </button>
            )}
        </Tooltip>
    );
}, { noop: true });

const PopoutVolume = ErrorBoundary.wrap(({ channelId, participantId }: { channelId: string; participantId: string; }) => {
    const participant = ChannelRTCStore.getParticipant(channelId, participantId);
    const userId = participant?.user?.id;
    if (participant?.type !== PARTICIPANT_TYPE_STREAM || !userId || userId === UserStore.getCurrentUser()?.id) return null;

    const popoutWindow = PopoutWindowStore.getWindow(`DISCORD_CALL_TILE_POPOUT_${channelId}_${participantId}`);

    return (
        <div
            style={{ display: "flex", alignItems: "center", color: "#fff" }}
            onClick={e => e.stopPropagation()}
            onDoubleClick={e => e.stopPropagation()}
        >
            <VolumeControl userId={userId} context="stream" currentWindow={popoutWindow ?? window} />
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

    patches: [
        {
            // Barra de controles de la llamada: botón junto al de "Abrir en ventana"
            find: "renderBottomRight=()=>",
            replacement: {
                match: /\i\?\(0,\i\.jsx\)\(\i\.\i,\{themeable:\i,popoutOpen:this\.popoutOpen,className:(\i\.\i),/,
                replace: "$self.renderBarButton(this.props,$1),$&"
            }
        },
        {
            // Ventana individual: volumen y pantalla completa junto a los botones que ya trae
            find: '"stay-on-top"',
            replacement: {
                match: /(\i)\.push\(\(0,\i\.jsx\)\(\i,\{channelId:(\i)\.id,participantId:(\i),hideWhenInactive:!1,idle:(\i)\},"stay-on-top"\)\),\i\.push\(\(0,\i\.jsx\)\((\i),\{/,
                replace: "$self.pushPopoutControls($1,{channelId:$2.id,participantId:$3,idle:$4,TileButton:$5}),$&"
            }
        }
    ],

    renderBarButton(props: any, className?: string) {
        try {
            const { channel, selectedParticipant } = props;
            if (!channel || selectedParticipant?.type !== PARTICIPANT_TYPE_STREAM) return null;

            return <BarButton key="vc-individual-stream" channelId={channel.id} participantId={selectedParticipant.id} className={className} />;
        } catch {
            return null;
        }
    },

    pushPopoutControls(buttons: React.ReactNode[], { channelId, participantId, idle, TileButton }: any) {
        try {
            buttons.push(
                <PopoutVolume key="vc-individual-volume" channelId={channelId} participantId={participantId} />,
                <TileButton
                    key="vc-individual-fullscreen"
                    icon={FullscreenIcon}
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
