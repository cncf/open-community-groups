import { LitElement, html, css } from '../vendor/lit-all.min.js';

/**
 * Social share buttons component
 * Provides buttons to share content on various social media platforms
 */
export class ShareButtons extends LitElement {
    static properties = {
        url: { type: String },
        title: { type: String },
        description: { type: String },
        compact: { type: Boolean },
    };

    static styles = css`
        :host {
            display: block;
        }

        .share-container {
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .share-label {
            font-size: 0.875rem;
            font-weight: 500;
            color: rgb(87 83 78);
            margin-right: 0.25rem;
        }

        .share-buttons {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
        }

        .share-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            padding: 0.5rem;
            border-radius: 0.375rem;
            transition: all 0.2s;
            cursor: pointer;
            border: 1px solid rgb(231 229 228);
            background-color: white;
            width: 2rem;
            height: 2rem;
        }

        .share-btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        .share-btn svg {
            width: 1rem;
            height: 1rem;
        }

        .share-btn.twitter:hover {
            background-color: rgb(29 161 242);
            border-color: rgb(29 161 242);
        }

        .share-btn.facebook:hover {
            background-color: rgb(24 119 242);
            border-color: rgb(24 119 242);
        }

        .share-btn.linkedin:hover {
            background-color: rgb(10 102 194);
            border-color: rgb(10 102 194);
        }

        .share-btn.copy:hover {
            background-color: rgb(87 83 78);
            border-color: rgb(87 83 78);
        }

        .share-btn:hover svg {
            fill: white;
        }

        .share-btn svg {
            fill: rgb(87 83 78);
        }

        .compact .share-btn {
            width: 1.75rem;
            height: 1.75rem;
        }

        .compact .share-btn svg {
            width: 0.875rem;
            height: 0.875rem;
        }

        .copy-feedback {
            position: absolute;
            background-color: rgb(41 37 36);
            color: white;
            padding: 0.25rem 0.5rem;
            border-radius: 0.25rem;
            font-size: 0.75rem;
            white-space: nowrap;
            pointer-events: none;
            z-index: 50;
            opacity: 0;
            transition: opacity 0.2s;
        }

        .copy-feedback.show {
            opacity: 1;
        }
    `;

    constructor() {
        super();
        this.url = window.location.href;
        this.title = document.title;
        this.description = '';
        this.compact = false;
    }

    getShareUrls() {
        const encodedUrl = encodeURIComponent(this.url);
        const encodedTitle = encodeURIComponent(this.title);
        const encodedDescription = encodeURIComponent(this.description);

        return {
            twitter: `https://twitter.com/intent/tweet?url=${encodedUrl}&text=${encodedTitle}`,
            facebook: `https://www.facebook.com/sharer/sharer.php?u=${encodedUrl}`,
            linkedin: `https://www.linkedin.com/sharing/share-offsite/?url=${encodedUrl}`,
        };
    }

    async copyToClipboard(e) {
        try {
            await navigator.clipboard.writeText(this.url);
            this.showCopyFeedback(e.currentTarget);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    }

    showCopyFeedback(button) {
        const feedback = button.querySelector('.copy-feedback');
        feedback.classList.add('show');
        setTimeout(() => {
            feedback.classList.remove('show');
        }, 2000);
    }

    shareOnPlatform(platform) {
        const urls = this.getShareUrls();
        window.open(urls[platform], '_blank', 'width=600,height=400');
    }

    render() {
        return html`
            <div class="share-container ${this.compact ? 'compact' : ''}">
                ${!this.compact
                    ? html`<span class="share-label">Share:</span>`
                    : ''}
                <div class="share-buttons">
                    <button
                        class="share-btn twitter"
                        @click="${() => this.shareOnPlatform('twitter')}"
                        title="Share on X (Twitter)"
                        aria-label="Share on X (Twitter)">
                        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                            <path
                                d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                        </svg>
                    </button>
                    <button
                        class="share-btn facebook"
                        @click="${() => this.shareOnPlatform('facebook')}"
                        title="Share on Facebook"
                        aria-label="Share on Facebook">
                        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                            <path
                                d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
                        </svg>
                    </button>
                    <button
                        class="share-btn linkedin"
                        @click="${() => this.shareOnPlatform('linkedin')}"
                        title="Share on LinkedIn"
                        aria-label="Share on LinkedIn">
                        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                            <path
                                d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
                        </svg>
                    </button>
                    <button
                        class="share-btn copy"
                        @click="${this.copyToClipboard}"
                        title="Copy link"
                        aria-label="Copy link to clipboard">
                        <svg
                            viewBox="0 0 24 24"
                            fill="none"
                            xmlns="http://www.w3.org/2000/svg">
                            <path
                                d="M16 13v-2a4 4 0 0 0-4-4h-2m2 10h-2a4 4 0 0 1-4-4v-2m4-4h2a4 4 0 0 1 4 4v2m-4 4h2a4 4 0 0 0 4-4v-2"
                                stroke="currentColor"
                                stroke-width="2"
                                stroke-linecap="round"
                                stroke-linejoin="round" />
                        </svg>
                        <span class="copy-feedback">Link copied!</span>
                    </button>
                </div>
            </div>
        `;
    }
}

customElements.define('share-buttons', ShareButtons);
